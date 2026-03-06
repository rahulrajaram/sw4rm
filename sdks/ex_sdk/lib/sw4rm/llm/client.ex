defmodule Sw4rm.LLM.Client do
  @moduledoc """
  Behaviour definition and shared types for LLM clients.

  All LLM client implementations must adopt this behaviour. This allows
  SW4RM agents to be provider-agnostic --- swap between Groq, Anthropic,
  or a mock client by changing a single option or environment variable.

  ## Response type

  Every `query/2` call returns `{:ok, response}` where `response` is a map
  with the following keys:

    * `:content`  -- the generated text (binary)
    * `:model`    -- the model that produced the response (binary)
    * `:usage`    -- token counts (`%{input_tokens: n, output_tokens: n}`) or `nil`
    * `:metadata` -- arbitrary provider-specific metadata (map)

  ## Options

  All callbacks accept a keyword list with:

    * `:system_prompt` -- optional system prompt for context
    * `:max_tokens`    -- maximum tokens to generate (default `4096`)
    * `:temperature`   -- sampling temperature 0.0-2.0 (default `1.0`)
    * `:model`         -- override the client's default model

  ## Error tuples

  Errors are returned as `{:error, reason}` where `reason` is one of:

    * `{:authentication, message}` -- invalid or missing credentials
    * `{:rate_limit, message}`     -- API rate limit exceeded (429)
    * `{:timeout, message}`        -- request timed out
    * `{:api_error, status, message}` -- other HTTP/API errors
    * `{:network, message}`        -- connection-level failures
  """

  @type usage :: %{
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer()
        }

  @type response :: %{
          content: String.t(),
          model: String.t(),
          usage: usage() | nil,
          metadata: map()
        }

  @type query_opts :: [
          system_prompt: String.t() | nil,
          max_tokens: pos_integer(),
          temperature: float(),
          model: String.t() | nil
        ]

  @type error_reason ::
          {:authentication, String.t()}
          | {:rate_limit, String.t()}
          | {:timeout, String.t()}
          | {:api_error, non_neg_integer(), String.t()}
          | {:network, String.t()}

  @doc """
  Send a prompt to the LLM and receive a complete response.

  Returns `{:ok, response}` on success or `{:error, reason}` on failure.
  See module documentation for the shapes of `response` and `reason`.
  """
  @callback query(prompt :: String.t(), opts :: query_opts()) ::
              {:ok, response()} | {:error, error_reason()}

  @doc """
  Stream a prompt response as a lazy enumerable of text chunks.

  Returns `{:ok, stream}` where `stream` implements `Enumerable` and
  yields binary chunks as they arrive. Returns `{:error, reason}` if
  the connection cannot be established.

  Note: streaming is best-effort. Clients that do not support server-sent
  events may fall back to returning the full response as a single chunk.
  """
  @callback stream_query(prompt :: String.t(), opts :: query_opts()) ::
              {:ok, Enumerable.t()} | {:error, error_reason()}

  # -- Shared helpers --------------------------------------------------------

  @doc """
  Extract standard options from a keyword list, applying defaults.

  Returns a map with `:system_prompt`, `:max_tokens`, `:temperature`,
  and `:model` keys.
  """
  @spec extract_opts(keyword()) :: map()
  def extract_opts(opts) do
    %{
      system_prompt: Keyword.get(opts, :system_prompt),
      max_tokens: Keyword.get(opts, :max_tokens, 4096),
      temperature: Keyword.get(opts, :temperature, 1.0),
      model: Keyword.get(opts, :model)
    }
  end

  @doc """
  Rough token estimate for rate-limiter budgeting.

  Uses the heuristic of ~4 characters per token, with a floor of 100 tokens.
  """
  @spec estimate_tokens(String.t(), String.t() | nil) :: pos_integer()
  def estimate_tokens(prompt, system_prompt \\ nil) do
    total = byte_size(prompt) + if(system_prompt, do: byte_size(system_prompt), else: 0)
    max(div(total, 4), 100)
  end
end
