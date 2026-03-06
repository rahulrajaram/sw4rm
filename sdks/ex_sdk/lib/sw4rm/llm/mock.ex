defmodule Sw4rm.LLM.Mock do
  @moduledoc """
  Mock LLM client for testing without making real API calls.

  Implements `Sw4rm.LLM.Client` using an `Agent` to maintain mutable state
  for responses, call counts, and call history. Responses cycle through
  a provided list or fall back to a default echo pattern.

  ## Usage

      {:ok, mock} = Sw4rm.LLM.Mock.start_link(
        responses: ["Hello!", "World!"]
      )

      {:ok, r1} = Sw4rm.LLM.Mock.query("Hi", client: mock)
      r1.content  #=> "Hello!"

      {:ok, r2} = Sw4rm.LLM.Mock.query("Again", client: mock)
      r2.content  #=> "World!"

      # Cycles back to the beginning
      {:ok, r3} = Sw4rm.LLM.Mock.query("More", client: mock)
      r3.content  #=> "Hello!"

      # Inspect call history
      2 = Sw4rm.LLM.Mock.call_count(mock)
      [first | _] = Sw4rm.LLM.Mock.call_history(mock)
      first.prompt  #=> "Hi"

  ## Custom response generator

  Pass a `:response_fn` that receives the prompt and returns a string:

      {:ok, mock} = Sw4rm.LLM.Mock.start_link(
        response_fn: fn prompt -> String.upcase(prompt) end
      )
  """

  @behaviour Sw4rm.LLM.Client

  alias Sw4rm.LLM.Client

  # -- Types -----------------------------------------------------------------

  @type call_record :: %{
          prompt: String.t(),
          system_prompt: String.t() | nil,
          max_tokens: pos_integer(),
          temperature: float(),
          model: String.t()
        }

  # -- Client API ------------------------------------------------------------

  @doc """
  Start a mock client Agent.

  ## Options

    * `:responses`    -- list of response strings to cycle through
    * `:response_fn`  -- `(String.t() -> String.t())` generator function
    * `:default_model`-- model name returned in responses (default `"mock-model"`)
    * `:name`         -- optional Agent name for registration

  Returns `{:ok, pid}` or `{:error, reason}`.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    initial_state = %{
      responses: Keyword.get(opts, :responses, []),
      response_fn: Keyword.get(opts, :response_fn),
      default_model: Keyword.get(opts, :default_model, "mock-model"),
      response_index: 0,
      call_count: 0,
      call_history: []
    }

    agent_opts =
      case Keyword.get(opts, :name) do
        nil -> []
        name -> [name: name]
      end

    Agent.start_link(fn -> initial_state end, agent_opts)
  end

  @doc """
  Stop a running mock client.
  """
  @spec stop(pid() | atom()) :: :ok
  def stop(mock) do
    Agent.stop(mock)
  end

  @doc """
  Return the number of queries made to this mock.
  """
  @spec call_count(pid() | atom()) :: non_neg_integer()
  def call_count(mock) do
    Agent.get(mock, & &1.call_count)
  end

  @doc """
  Return the full call history as a list of `call_record` maps.

  Most recent call is last in the list.
  """
  @spec call_history(pid() | atom()) :: [call_record()]
  def call_history(mock) do
    Agent.get(mock, & &1.call_history)
  end

  @doc """
  Reset call count, history, and response index.
  """
  @spec reset(pid() | atom()) :: :ok
  def reset(mock) do
    Agent.update(mock, fn s ->
      %{s | call_count: 0, call_history: [], response_index: 0}
    end)
  end

  # -- Behaviour callbacks ---------------------------------------------------

  @doc """
  Return a mock response.

  Pass the mock Agent pid/name via `:client` in opts.

  ## Examples

      {:ok, mock} = Sw4rm.LLM.Mock.start_link(responses: ["test"])
      {:ok, resp} = Sw4rm.LLM.Mock.query("hello", client: mock)
      resp.content  #=> "test"
  """
  @impl true
  @spec query(String.t(), keyword()) :: {:ok, Client.response()} | {:error, Client.error_reason()}
  def query(prompt, opts \\ []) do
    mock = Keyword.fetch!(opts, :client)
    parsed = Client.extract_opts(opts)

    {content, model} =
      Agent.get_and_update(mock, fn state ->
        record = %{
          prompt: prompt,
          system_prompt: parsed.system_prompt,
          max_tokens: parsed.max_tokens,
          temperature: parsed.temperature,
          model: parsed.model || state.default_model
        }

        content = generate_content(state, prompt)
        next_index = next_response_index(state)

        updated = %{
          state
          | call_count: state.call_count + 1,
            call_history: state.call_history ++ [record],
            response_index: next_index
        }

        {{content, record.model}, updated}
      end)

    response = %{
      content: content,
      model: model,
      usage: %{
        input_tokens: max(div(byte_size(prompt), 4), 1),
        output_tokens: max(div(byte_size(content), 4), 1)
      },
      metadata: %{provider: "mock", mock: true}
    }

    {:ok, response}
  end

  @doc """
  Stream a mock response as a list of word chunks.

  Splits the mock response on whitespace to simulate streaming.
  """
  @impl true
  @spec stream_query(String.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Client.error_reason()}
  def stream_query(prompt, opts \\ []) do
    case query(prompt, opts) do
      {:ok, response} ->
        words = String.split(response.content)

        chunks =
          words
          |> Enum.with_index()
          |> Enum.map(fn {word, i} ->
            if i < length(words) - 1, do: word <> " ", else: word
          end)

        {:ok, chunks}

      error ->
        error
    end
  end

  # -- Private ---------------------------------------------------------------

  defp generate_content(state, prompt) do
    cond do
      state.response_fn != nil ->
        state.response_fn.(prompt)

      state.responses != [] ->
        Enum.at(state.responses, rem(state.response_index, length(state.responses)))

      true ->
        truncated = if byte_size(prompt) > 100, do: binary_part(prompt, 0, 100), else: prompt
        "Mock response to: #{truncated}"
    end
  end

  defp next_response_index(%{responses: []}), do: 0

  defp next_response_index(%{responses: responses, response_index: idx}) do
    rem(idx + 1, length(responses))
  end
end
