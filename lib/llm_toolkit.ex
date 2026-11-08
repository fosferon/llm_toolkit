defmodule LlmToolkit do
  @moduledoc """
  Base code tools for agentic LLM execution.

  LlmToolkit provides the fundamental tools every agentic consumer needs to
  interact with a filesystem, shell, and the web — read, write, edit, bash,
  grep, glob, tree, and http_get. Each tool implements `LlmToolkit.ToolResolver`.

  ## Usage

      # Use the default tool resolver (cwd = ".")
      defmodule MyAgent do
        @resolver LlmToolkit.CodeTools

        def run(task) do
          MyAgent.Loop.run(task, @resolver, [])
        end
      end

      # Use with a specific working directory
      resolver = {LlmToolkit.CodeTools, "/path/to/project"}
  """

  alias LlmToolkit.CodeTools
  alias LlmToolkit.Tool.Call

  @doc """
  Creates a ToolResolver function bound to a working directory.

  Returns a tuple `{LlmToolkit.CodeTools, cwd}` suitable for use
  as a resolver in any agent loop that accepts `ToolResolver` modules.

  ## Examples

      iex> LlmToolkit.resolver("/tmp/project")
      {LlmToolkit.CodeTools, "/tmp/project"}
  """
  @spec resolver(String.t()) :: {module(), String.t()}
  def resolver(cwd) when is_binary(cwd) do
    {CodeTools, cwd}
  end

  @doc """
  Creates a resolver closure for use in contexts that expect
  a simple function, not a tuple.

  ## Examples

      resolver = LlmToolkit.resolver_fn("/tmp/project")
      {:ok, content} = resolver.(%Call{name: "read_file", arguments: %{"path" => "README.md"}})
  """
  @spec resolver_fn(String.t()) :: (Call.t() -> {:ok, String.t()} | {:error, String.t()})
  def resolver_fn(cwd) when is_binary(cwd) do
    fn %Call{} = call ->
      CodeTools.resolve(call, cwd)
    end
  end
end
