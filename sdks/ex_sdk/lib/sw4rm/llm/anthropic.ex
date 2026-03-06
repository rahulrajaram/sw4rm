defmodule Sw4rm.LLM.Anthropic do
  @moduledoc """
  LLM client for the Anthropic Messages API.

  Implements `Sw4rm.LLM.Client` using raw HTTP via OTP's `:httpc` module.
  No external HTTP dependencies are required.

  ## Credentials (resolved in order)

    1. `:api_key` option passed to `new/1`
    2. `ANTHROPIC_API_KEY` environment variable
    3. `~/.anthropic` file (plain text, first line)

  ## Default model

  `claude-sonnet-4-20250514`, overridable via `:default_model` option or
  `ANTHROPIC_DEFAULT_MODEL` environment variable.

  ## API details

  Uses the Anthropic Messages API (`/v1/messages`) with:

    * `x-api-key` header for authentication
    * `anthropic-version: 2023-06-01` header
    * System prompt via top-level `system` field (not in messages array)
    * Text extracted from content blocks in the response

  ## Rate limiting

  If a `Sw4rm.LLM.RateLimiter` is running under the default name,
  requests automatically acquire tokens and report 429s. Pass
  `:rate_limiter` option to specify a different server name, or `nil`
  to disable.

  ## Usage

      {:ok, client} = Sw4rm.LLM.Anthropic.new(api_key: "sk-ant-...")
      {:ok, response} = Sw4rm.LLM.Anthropic.query(client, "Explain monads.",
        system_prompt: "Be concise."
      )
      IO.puts(response.content)
  """

  @behaviour Sw4rm.LLM.Client

  alias Sw4rm.LLM.Client

  require Logger

  @default_model "claude-sonnet-4-20250514"
  @api_url ~c"https://api.anthropic.com/v1/messages"
  @content_type ~c"application/json"
  @anthropic_version "2023-06-01"

  # -- Types -----------------------------------------------------------------

  @type t :: %__MODULE__{
          api_key: String.t(),
          default_model: String.t(),
          timeout_ms: pos_integer(),
          rate_limiter: GenServer.server() | nil
        }

  defstruct [:api_key, :default_model, :timeout_ms, :rate_limiter]

  # -- Construction ----------------------------------------------------------

  @doc """
  Create a new Anthropic client struct.

  ## Options

    * `:api_key`       -- API key (falls back to env / dotfile)
    * `:default_model` -- model name (default `"claude-sonnet-4-20250514"`)
    * `:timeout_ms`    -- HTTP timeout in milliseconds (default `300_000`)
    * `:rate_limiter`  -- rate limiter server name (default `Sw4rm.LLM.RateLimiter`, `nil` to disable)

  Returns `{:ok, client}` or `{:error, {:authentication, message}}`.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Client.error_reason()}
  def new(opts \\ []) do
    api_key = resolve_api_key(opts)

    case api_key do
      nil ->
        {:error,
         {:authentication,
          "No Anthropic API key. Set ANTHROPIC_API_KEY, pass :api_key, or create ~/.anthropic"}}

      key ->
        ensure_httpc_started()

        client = %__MODULE__{
          api_key: key,
          default_model:
            Keyword.get(opts, :default_model) ||
              System.get_env("ANTHROPIC_DEFAULT_MODEL") ||
              @default_model,
          timeout_ms: Keyword.get(opts, :timeout_ms, 300_000),
          rate_limiter: Keyword.get(opts, :rate_limiter, Sw4rm.LLM.RateLimiter)
        }

        {:ok, client}
    end
  end

  # -- Behaviour callbacks ---------------------------------------------------

  @doc """
  Send a prompt to Anthropic and receive a complete response.

  The first argument is the prompt string. Pass `:client` in opts
  for an explicit client struct, or credentials will be resolved
  from options/environment.

  See `Sw4rm.LLM.Client` for supported options.
  """
  @impl true
  @spec query(String.t(), keyword()) :: {:ok, Client.response()} | {:error, Client.error_reason()}
  def query(prompt, opts \\ []) do
    with {:ok, client} <- client_from_opts(opts) do
      do_query(client, prompt, opts)
    end
  end

  @doc """
  Stream a prompt response as a list of text chunks.

  Since `:httpc` does not natively support streaming SSE parsing, this
  implementation collects the full response and returns it as a single-element
  list wrapped in `{:ok, list}`. For true streaming, consider a dedicated
  HTTP client.
  """
  @impl true
  @spec stream_query(String.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Client.error_reason()}
  def stream_query(prompt, opts \\ []) do
    case query(prompt, opts) do
      {:ok, response} -> {:ok, [response.content]}
      error -> error
    end
  end

  # -- Instance-based API (non-behaviour) ------------------------------------

  @doc """
  Query using an explicit client struct (for direct, non-behaviour usage).

  This is the instance-method equivalent. The behaviour callbacks
  `query/2` and `stream_query/2` require the client to be passed via
  the `:client` option in opts.
  """
  @spec do_query(t(), String.t(), keyword()) ::
          {:ok, Client.response()} | {:error, Client.error_reason()}
  def do_query(%__MODULE__{} = client, prompt, opts \\ []) do
    parsed = Client.extract_opts(opts)
    model = parsed.model || client.default_model
    estimated = Client.estimate_tokens(prompt, parsed.system_prompt)

    with :ok <- maybe_acquire(client.rate_limiter, estimated) do
      body = build_request_body(prompt, parsed, model)

      case http_post(client, body) do
        {:ok, status, resp_body} when status in 200..299 ->
          result = parse_response(resp_body, model)
          maybe_record_success(client.rate_limiter)
          {:ok, result}

        {:ok, 401, resp_body} ->
          {:error, {:authentication, "Anthropic authentication failed: #{truncate(resp_body)}"}}

        {:ok, 403, resp_body} ->
          {:error, {:authentication, "Anthropic permission denied: #{truncate(resp_body)}"}}

        {:ok, 429, resp_body} ->
          maybe_record_rate_limit(client.rate_limiter)
          {:error, {:rate_limit, "Anthropic rate limit exceeded: #{truncate(resp_body)}"}}

        {:ok, status, resp_body} ->
          # Check for billing errors in the body
          lower = String.downcase(resp_body)

          if String.contains?(lower, "credit balance") or String.contains?(lower, "billing") do
            {:error, {:authentication, "Anthropic billing error: #{truncate(resp_body)}"}}
          else
            {:error,
             {:api_error, status, "Anthropic API error (#{status}): #{truncate(resp_body)}"}}
          end

        {:error, :timeout} ->
          {:error, {:timeout, "Anthropic request timed out"}}

        {:error, reason} ->
          msg = inspect(reason)

          if String.contains?(msg, "timeout") do
            {:error, {:timeout, "Anthropic request timed out: #{msg}"}}
          else
            {:error, {:network, "Anthropic network error: #{msg}"}}
          end
      end
    end
  end

  # -- Private ---------------------------------------------------------------

  defp client_from_opts(opts) do
    case Keyword.get(opts, :client) do
      %__MODULE__{} = c -> {:ok, c}
      nil -> new(opts)
    end
  end

  defp resolve_api_key(opts) do
    with nil <- Keyword.get(opts, :api_key),
         nil <- get_env_trimmed("ANTHROPIC_API_KEY"),
         nil <- load_key_file("~/.anthropic") do
      nil
    end
  end

  defp get_env_trimmed(key) do
    case System.get_env(key) do
      nil -> nil
      val -> String.trim(val)
    end
  end

  defp load_key_file(path) do
    expanded = Path.expand(path)

    if File.exists?(expanded) do
      case File.read(expanded) do
        {:ok, content} ->
          trimmed = String.trim(content)
          if trimmed == "", do: nil, else: trimmed

        _ ->
          nil
      end
    else
      nil
    end
  end

  defp build_request_body(prompt, parsed, model) do
    base = %{
      "model" => model,
      "messages" => [%{"role" => "user", "content" => prompt}],
      "max_tokens" => parsed.max_tokens,
      "temperature" => parsed.temperature
    }

    body =
      case parsed.system_prompt do
        nil -> base
        sys -> Map.put(base, "system", sys)
      end

    Jason.encode!(body)
  end

  defp http_post(client, body) do
    headers = [
      {~c"x-api-key", String.to_charlist(client.api_key)},
      {~c"anthropic-version", String.to_charlist(@anthropic_version)},
      {~c"content-type", @content_type}
    ]

    http_opts = [
      timeout: client.timeout_ms,
      connect_timeout: min(client.timeout_ms, 10_000),
      ssl: ssl_opts()
    ]

    case :httpc.request(
           :post,
           {@api_url, headers, @content_type, String.to_charlist(body)},
           http_opts,
           [{:body_format, :binary}]
         ) do
      {:ok, {{_http_version, status, _reason}, _resp_headers, resp_body}} ->
        {:ok, status, to_string(resp_body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_response(body, fallback_model) do
    decoded = Jason.decode!(body)

    # Extract text from content blocks
    content =
      decoded
      |> Map.get("content", [])
      |> Enum.filter(fn block -> Map.get(block, "type") == "text" end)
      |> Enum.map(fn block -> Map.get(block, "text", "") end)
      |> Enum.join()
      |> String.trim()

    model = Map.get(decoded, "model", fallback_model)

    usage =
      case Map.get(decoded, "usage") do
        nil ->
          nil

        u ->
          input_tokens = Map.get(u, "input_tokens", 0)
          output_tokens = Map.get(u, "output_tokens", 0)

          %{
            input_tokens: input_tokens,
            output_tokens: output_tokens
          }
      end

    %{
      content: content,
      model: model,
      usage: usage,
      metadata: %{
        provider: "anthropic",
        id: Map.get(decoded, "id"),
        stop_reason: Map.get(decoded, "stop_reason")
      }
    }
  end

  defp maybe_acquire(nil, _tokens), do: :ok

  defp maybe_acquire(server, tokens) do
    if process_alive?(server) do
      Sw4rm.LLM.RateLimiter.acquire(server, tokens)
    else
      :ok
    end
  end

  defp maybe_record_success(nil), do: :ok

  defp maybe_record_success(server) do
    if process_alive?(server), do: Sw4rm.LLM.RateLimiter.record_success(server)
    :ok
  end

  defp maybe_record_rate_limit(nil), do: :ok

  defp maybe_record_rate_limit(server) do
    if process_alive?(server), do: Sw4rm.LLM.RateLimiter.record_rate_limit(server)
    :ok
  end

  defp process_alive?(name) when is_atom(name), do: Process.whereis(name) != nil
  defp process_alive?(pid) when is_pid(pid), do: Process.alive?(pid)
  defp process_alive?(_), do: false

  defp ensure_httpc_started do
    :inets.start()
    :ssl.start()
  end

  defp ssl_opts do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 3,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end

  defp truncate(text) when byte_size(text) > 500, do: binary_part(text, 0, 500) <> "..."
  defp truncate(text), do: text
end
