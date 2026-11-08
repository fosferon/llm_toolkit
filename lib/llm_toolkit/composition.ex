defmodule LlmToolkit.Composition do
  @moduledoc """
  Compose multiple tool resolvers into one.

  Allows consumers to merge base tools (from LlmToolkit.CodeTools) with
  their own domain-specific tools into a single resolver.

  ## Example

      # Base tools + domain tools
      resolver = LlmToolkit.Composition.new([
        {LlmToolkit.CodeTools, "/project"},
        MyApp.DomainTools
      ])

      {:ok, tools} = resolver.available_tools()
      # Returns all base tools + domain tools

      {:ok, result} = resolver.resolve(%Call{name: "read_file", arguments: %{...}})
      # Dispatches to CodeTools

      {:ok, result} = resolver.resolve(%Call{name: "search", arguments: %{...}})
      # Dispatches to MyApp.DomainTools

  ## Priority

  Resolvers are tried in order. First match wins. This means consumer-specific
  tools can override base tools if needed (e.g., a custom bash tool with
  sandboxing).

  ## Resolver formats

  Each element in the list can be:
  - A module implementing `LlmToolkit.ToolResolver` (cwd = ".")
  - A `{module, cwd}` tuple for cwd-aware resolvers like CodeTools
  """

  alias LlmToolkit.Tool
  alias LlmToolkit.Tool.Call

  @enforce_keys [:resolvers]
  defstruct [:resolvers]

  @type t :: %__MODULE__{resolvers: [{module(), String.t()}]}

  @doc """
  Creates a composed resolver from a list of resolver specs.

  Each spec is either a module (uses "." as cwd) or a `{module, cwd}` tuple.
  """
  @spec new([module() | {module(), String.t()}]) :: t()
  def new(specs) when is_list(specs) do
    resolvers =
      Enum.map(specs, fn
        {mod, cwd} when is_atom(mod) and is_binary(cwd) -> {mod, cwd}
        mod when is_atom(mod) -> {mod, "."}
      end)

    %__MODULE__{resolvers: resolvers}
  end

  @doc """
  Returns all available tools from all composed resolvers.

  Tools from earlier resolvers appear first. Duplicate tool names are kept
  (the first resolver to match a tool name wins during dispatch).
  """
  @spec available_tools(t()) :: [Tool.t()]
  def available_tools(%__MODULE__{resolvers: resolvers}) do
    Enum.flat_map(resolvers, fn {mod, _cwd} ->
      mod.available_tools()
    end)
  end

  @doc """
  Resolves a tool call by trying each resolver in order.

  The first resolver to return something other than "Unknown tool" wins.
  """
  @spec resolve(t(), Call.t()) :: {:ok, String.t()} | {:error, String.t()}
  def resolve(%__MODULE__{resolvers: resolvers}, %Call{} = call) do
    Enum.reduce_while(resolvers, {:error, "Unknown tool: #{call.name}"}, fn {mod, cwd}, _acc ->
      case try_resolve(mod, cwd, call) do
        {:ok, _} = result -> {:halt, result}
        {:error, "Unknown tool:" <> _} -> {:cont, {:error, "Unknown tool: #{call.name}"}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  @doc """
  Returns the dispatch recipe for a tool name by checking each resolver.

  First non-nil recipe wins.
  """
  @spec dispatch_recipe(t(), String.t()) :: (map() -> map()) | nil
  def dispatch_recipe(%__MODULE__{resolvers: resolvers}, tool_name) do
    Enum.find_value(resolvers, fn {mod, _cwd} ->
      if Code.ensure_loaded?(mod) and function_exported?(mod, :dispatch_recipe, 1) do
        mod.dispatch_recipe(tool_name)
      end
    end)
  end

  defp try_resolve(mod, cwd, call) do
    if Code.ensure_loaded?(mod) and function_exported?(mod, :resolve, 2) do
      mod.resolve(call, cwd)
    else
      mod.resolve(call)
    end
  end
end
