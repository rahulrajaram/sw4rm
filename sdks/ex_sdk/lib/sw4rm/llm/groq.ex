defmodule Sw4rm.LLM.Groq do
  @moduledoc """
  LLM client for the Groq API.

  Implements `Sw4rm.LLM.Client` using raw HTTP via OTP's `:httpc` module.
  No external HTTP dependencies are required.

  ## Credentials (resolved in order)

    1. `:api_key` option passed to `new/1`
    2. `GROQ_API_KEY` environment variable
    3. `~/.groq` file (plain text, first line)

  ## Default model

  `llama-3.3-70b-versatile`, overridable via `:default_model` option or
  `GROQ_DEFAULT_MODEL` environment variable.

  ## Rate limiting

  If a `Sw4rm.LLM.RateLimiter` is running under the default name,
  requests automatically acquire tokens and report 429s. Pass
  `:rate_limiter` option to specify a different server name, or `nil`
  to disable.

  ## Usage

      {:ok, client} = Sw4rm.LLM.Groq.new(api_key: "gsk_...")
      {:ok, response} = Sw4rm.LLM.Groq.query(client, "Hello!", system_prompt: "Be brief.")
      IO.puts(response.content)
  """

  @behaviour Sw4rm.LLM.Client

  alias Sw4rm.LLM.Client

  require Logger

  @default_model "llama-3.3-70b-versatile"
  @api_url ~c"https://api.groq.com/openai/v1/chat/completions"
  @content_type ~c"application/json"

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
  Create a new Groq client struct.

  ## Options

    * `:api_key`       -- API key (falls back to env / dotfile)
    * `:default_model` -- model name (default `"llama-3.3-70b-versatile"`)
    * `:timeout_ms`    -- HTTP timeout in milliseconds (default `120_000`)
    * `:rate_limiter`  -- rate limiter server name (default `Sw4rm.LLM.RateLimiter`, `nil` to disable)

  Returns `{:ok, client}` or `{:error, {:authentication, message}}`.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Client.error_reason()}
  def new(opts \\ []) do
    api_key = resolve_api_key(opts)

    case api_key do
      nil ->
        {:error,
         {:authentication, "No Groq API key. Set GROQ_API_KEY, pass :api_key, or create ~/.groq"}}

      key ->
        ensure_httpc_started()

        client = %__MODULE__{
          api_key: key,
          default_model:
            Keyword.get(opts, :default_model) ||
              System.get_env("GROQ_DEFAULT_MODEL") ||
              @default_model,
          timeout_ms: Keyword.get(opts, :timeout_ms, 120_000),
          rate_limiter: Keyword.get(opts, :rate_limiter, Sw4rm.LLM.RateLimiter)
        }

        {:ok, client}
    end
  end

  # -- Behaviour callbacks ---------------------------------------------------

  @doc """
  Send a prompt to Groq and receive a complete response.

  The first argument is the client struct returned by `new/1`.
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
          {:error, {:authentication, "Groq authentication failed: #{truncate(resp_body)}"}}

        {:ok, 429, resp_body} ->
          maybe_record_rate_limit(client.rate_limiter)
          {:error, {:rate_limit, "Groq rate limit exceeded: #{truncate(resp_body)}"}}

        {:ok, status, resp_body} ->
          {:error, {:api_error, status, "Groq API error (#{status}): #{truncate(resp_body)}"}}

        {:error, :timeout} ->
          {:error, {:timeout, "Groq request timed out"}}

        {:error, reason} ->
          msg = inspect(reason)

          if String.contains?(msg, "timeout") do
            {:error, {:timeout, "Groq request timed out: #{msg}"}}
          else
            {:error, {:network, "Groq network error: #{msg}"}}
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
         nil <- get_env_trimmed("GROQ_API_KEY"),
         nil <- load_key_file("~/.groq") do
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
    messages =
      case parsed.system_prompt do
        nil -> [%{"role" => "user", "content" => prompt}]
        sys -> [%{"role" => "system", "content" => sys}, %{"role" => "user", "content" => prompt}]
      end

    Jason.encode!(%{
      "model" => model,
      "messages" => messages,
      "max_tokens" => parsed.max_tokens,
      "temperature" => parsed.temperature
    })
  end

  defp http_post(client, body) do
    headers = [
      {~c"authorization", String.to_charlist("Bearer #{client.api_key}")},
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

    content =
      case get_in(decoded, ["choices", Access.at(0), "message", "content"]) do
        nil -> ""
        text -> text
      end

    model = Map.get(decoded, "model", fallback_model)

    usage =
      case Map.get(decoded, "usage") do
        nil ->
          nil

        u ->
          %{
            input_tokens: Map.get(u, "prompt_tokens", 0),
            output_tokens: Map.get(u, "completion_tokens", 0)
          }
      end

    %{
      content: content,
      model: model,
      usage: usage,
      metadata: %{provider: "groq", id: Map.get(decoded, "id")}
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
