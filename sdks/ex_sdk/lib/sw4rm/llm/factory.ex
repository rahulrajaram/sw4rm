defmodule Sw4rm.LLM.Factory do
  @moduledoc """
  Factory for creating LLM clients based on configuration.

  Provides a single entry point for creating the appropriate LLM client
  based on explicit options or environment variables. This allows agent
  code to remain provider-agnostic.

  ## Client types

    * `"groq"`      -- `Sw4rm.LLM.Groq` (Groq API)
    * `"anthropic"` -- `Sw4rm.LLM.Anthropic` (Anthropic Messages API)
    * `"mock"`      -- `Sw4rm.LLM.Mock` (testing, no API calls)

  ## Environment variables

    * `LLM_CLIENT_TYPE`   -- default client type (default `"mock"`)
    * `LLM_DEFAULT_MODEL` -- default model name

  ## Usage

      # Auto-detect from environment
      {:ok, {module, client}} = Sw4rm.LLM.Factory.create_llm_client()

      # Explicit type
      {:ok, {module, client}} = Sw4rm.LLM.Factory.create_llm_client(client_type: "anthropic")

      # Use the client
      {:ok, response} = module.query("Hello!", client: client)

      # Mock for testing
      {:ok, {module, mock}} = Sw4rm.LLM.Factory.create_llm_client(
        client_type: "mock",
        responses: ["test response"]
      )
  """

  require Logger

  @doc """
  Create an LLM client based on options or environment configuration.

  ## Options

    * `:client_type` -- `"groq"`, `"anthropic"`, or `"mock"` (default from env or `"mock"`)
    * `:model`       -- default model override (from env `LLM_DEFAULT_MODEL`)
    * All other options are forwarded to the specific client constructor.

  ## Return value

  Returns `{:ok, {module, client_or_pid}}` where:

    * `module` is the client module (e.g., `Sw4rm.LLM.Groq`)
    * `client_or_pid` is the client struct (Groq/Anthropic) or pid (Mock)

  This tuple allows callers to dispatch: `module.query(prompt, client: client_or_pid)`.

  Returns `{:error, reason}` if the client type is unknown or initialization fails.
  """
  @spec create_llm_client(keyword()) ::
          {:ok, {module(), term()}} | {:error, term()}
  def create_llm_client(opts \\ []) do
    client_type =
      opts
      |> Keyword.get(:client_type)
      |> case do
        nil -> System.get_env("LLM_CLIENT_TYPE") || "mock"
        type -> type
      end
      |> String.downcase()

    model = Keyword.get(opts, :model) || System.get_env("LLM_DEFAULT_MODEL")
    remaining_opts = Keyword.drop(opts, [:client_type, :model])

    client_opts =
      if model do
        Keyword.put(remaining_opts, :default_model, model)
      else
        remaining_opts
      end

    case client_type do
      "groq" ->
        Logger.info("Creating Groq LLM client")
        create_groq(client_opts)

      "anthropic" ->
        Logger.info("Creating Anthropic LLM client")
        create_anthropic(client_opts)

      "mock" ->
        Logger.info("Creating Mock LLM client")
        create_mock(client_opts)

      unknown ->
        {:error,
         "Unknown LLM client type: #{inspect(unknown)}. " <>
           "Valid types: \"groq\", \"anthropic\", \"mock\""}
    end
  end

  @doc """
  Deprecated. Use `create_llm_client/1` instead.
  """
  @deprecated "Use create_llm_client/1 instead"
  @spec create_client(keyword()) ::
          {:ok, {module(), term()}} | {:error, term()}
  def create_client(opts \\ []), do: create_llm_client(opts)

  # -- Private ---------------------------------------------------------------

  defp create_groq(opts) do
    case Sw4rm.LLM.Groq.new(opts) do
      {:ok, client} -> {:ok, {Sw4rm.LLM.Groq, client}}
      error -> error
    end
  end

  defp create_anthropic(opts) do
    case Sw4rm.LLM.Anthropic.new(opts) do
      {:ok, client} -> {:ok, {Sw4rm.LLM.Anthropic, client}}
      error -> error
    end
  end

  defp create_mock(opts) do
    case Sw4rm.LLM.Mock.start_link(opts) do
      {:ok, pid} -> {:ok, {Sw4rm.LLM.Mock, pid}}
      error -> error
    end
  end
end
