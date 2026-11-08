defmodule LlmToolkit.AgentResolver do
  @moduledoc """
  Configurable tool resolver.

  Host applications `use` this module with a `:tools` option listing their
  tool handler modules. Each tool module must export:

    * `definition/0` → `LlmToolkit.Tool.t()`
    * `execute/2` → `(map(), map()) -> {:ok, String.t()} | {:error, String.t()}`
    * `sensitive_fields/0` → `[String.t()]` (optional)

  The generated module implements `LlmToolkit.ToolResolver` and adds
  context-aware `resolve/2` and `sensitive_fields_for/1` helpers.

  ## Example

      defmodule MyApp.Tools.Resolver do
        use LlmToolkit.AgentResolver, tools: [
          MyApp.Tools.Search
        ]
      end

  ## Error handling

  Tool execution that raises is rescued, logged, and returned as
  `{:error, "Tool execution failed: …"}`. This prevents a single buggy
  tool from crashing the agent loop.
  """

  defmacro __using__(opts) do
    tool_modules = Keyword.fetch!(opts, :tools)

    quote bind_quoted: [tool_modules: tool_modules] do
      @behaviour LlmToolkit.ToolResolver

      alias LlmToolkit.Tool.Call

      require Logger

      @tool_modules tool_modules

      @impl true
      def available_tools do
        Enum.map(@tool_modules, fn mod ->
          mod.definition()
        end)
      end

      @doc """
      Return the list of sensitive argument fields for a tool name.

      Used by telemetry handlers to scrub PII from metadata. Each tool
      module owns its own list via an optional `sensitive_fields/0`
      function; this dispatch is the single place that maps tool names
      to modules for that purpose.

      Unknown tool names return `[]` — better to emit un-redacted
      telemetry for an unknown tool than to crash the handler.
      """
      @spec sensitive_fields_for(String.t()) :: [String.t()]
      def sensitive_fields_for(name) do
        case find_module(name) do
          nil ->
            []

          mod ->
            if function_exported?(mod, :sensitive_fields, 0) do
              mod.sensitive_fields()
            else
              []
            end
        end
      end

      @doc """
      Resolve a tool call WITHOUT session context.

      This is the behaviour callback. It delegates to `resolve/2` with
      an empty context map.
      """
      @impl true
      def resolve(%Call{} = call) do
        resolve(call, %{})
      end

      @doc """
      Resolve a tool call WITH session context.

      Called by the closure built in `LlmToolkit.SessionTools.prepare/3`.
      The context map is opaque to the resolver — its shape is defined
      by the host application and the individual tool modules.
      """
      @spec resolve(Call.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
      def resolve(%Call{name: name, arguments: args}, context) do
        case find_module(name) do
          nil ->
            {:error, "Unknown tool: #{name}"}

          mod ->
            try do
              mod.execute(args, context)
            rescue
              e ->
                Logger.error("[AgentResolver] #{name} raised: #{Exception.message(e)}")
                {:error, "Tool execution failed: #{Exception.message(e)}"}
            end
        end
      end

      defp find_module(name) do
        Enum.find(@tool_modules, fn mod -> mod.definition().name == name end)
      end
    end
  end
end
