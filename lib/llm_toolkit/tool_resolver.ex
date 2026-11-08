defmodule LlmToolkit.ToolResolver do
  @moduledoc """
  Behaviour for resolving tool calls to execution functions.

  Host applications implement this behaviour to map tool names to actual
  execution logic. The agentic loop uses the resolver to dispatch tool
  calls requested by the LLM.

  ## Example

      defmodule MyApp.ToolResolver do
        @behaviour LlmToolkit.ToolResolver

        @impl true
        def resolve(%LlmToolkit.Tool.Call{name: "search", arguments: args}) do
          case MyApp.Search.run(args["query"]) do
            {:ok, results} -> {:ok, format_results(results)}
            {:error, reason} -> {:error, inspect(reason)}
          end
        end

        def resolve(%LlmToolkit.Tool.Call{name: name}) do
          {:error, "Unknown tool: \#{name}"}
        end

        @impl true
        def available_tools do
          [
            %LlmToolkit.Tool{
              name: "search",
              description: "Search the knowledge base",
              parameters: %{"type" => "object", "properties" => %{"query" => %{"type" => "string"}}}
            }
          ]
        end
      end

  ## Dispatch Recipes (Optional)

  Implement `dispatch_recipe/1` to delegate a tool to an orchestrated
  sub-tool pipeline instead of direct `resolve/1` execution.

      @impl true
      def dispatch_recipe("research_domain"), do: &MyRecipes.research_domain/1
      def dispatch_recipe(_), do: nil
  """

  alias LlmToolkit.Tool
  alias LlmToolkit.Tool.Call

  @doc """
  Resolves and executes a tool call, returning the result content.

  ## Returns

    * `{:ok, content}` — Successful execution with string content
    * `{:error, reason}` — Execution failed with string reason
  """
  @callback resolve(Call.t()) :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Returns the list of tools available through this resolver.
  """
  @callback available_tools() :: [Tool.t()]

  @doc """
  Returns a dispatch recipe for the given tool name, or `nil`.

  A recipe is a function that takes the tool call's arguments (a map)
  and returns an execution plan with `:serial`, `:parallel`, and optional
  `:compose` keys. When `nil` is returned, the tool is executed directly
  via `resolve/1`.
  """
  @callback dispatch_recipe(String.t()) :: (map() -> map()) | nil

  @optional_callbacks [dispatch_recipe: 1]
end
