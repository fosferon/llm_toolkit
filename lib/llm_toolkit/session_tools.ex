defmodule LlmToolkit.SessionTools do
  @moduledoc """
  Integration layer: filters available tools by session declaration and
  builds a context-bound resolver closure.

  Called by host applications before each turn to compose the
  `{tools, resolve_tool}` tuple that the agent loop passes
  through to the LLM adapter.

  ## Design Decision: Closure over Process Dictionary

  Context is threaded via a closure that captures `session_context` at
  call time. This is pure, thread-safe across concurrent turns, and
  unit-testable. Process dictionary was considered but rejected — it's
  a leak risk and couples the resolver to the calling process identity.
  """

  require Logger

  @doc """
  Prepare tools and resolver for a session turn.

  ## Parameters

    * `resolver_mod` — module implementing `LlmToolkit.ToolResolver` with
      an additional `resolve/2` callback for context-aware dispatch.
      Typically generated via `use LlmToolkit.AgentResolver, tools: […]`.
    * `declared_tool_names` — list of tool name strings from host
      configuration (e.g., `["search"]`). Nil or empty list means
      no tools — adapter takes single-shot path.
    * `session_context` — map with session-scoped data. Shape is opaque to
      this module; it is forwarded verbatim to `resolver_mod.resolve/2`.

  ## Returns

    * `{filtered_tools, resolver_fn}` — non-empty tools and a closure
      that dispatches calls with session context bound
    * `{[], nil}` — when no tools are declared or none match available tools
  """
  @spec prepare(module(), list(String.t()) | nil, map()) ::
          {[LlmToolkit.Tool.t()],
           (LlmToolkit.Tool.Call.t() -> {:ok, String.t()} | {:error, String.t()}) | nil}
  def prepare(_resolver_mod, nil, _session_context), do: {[], nil}
  def prepare(_resolver_mod, [], _session_context), do: {[], nil}

  def prepare(resolver_mod, declared_tool_names, session_context)
      when is_list(declared_tool_names) do
    all_tools = resolver_mod.available_tools()
    available_names = MapSet.new(Enum.map(all_tools, & &1.name))
    declared_set = MapSet.new(declared_tool_names)

    # Warn about unknown tool names (spec drift)
    unknown = MapSet.difference(declared_set, available_names)

    if MapSet.size(unknown) > 0 do
      Logger.warning(
        "[SessionTools] Unknown tools declared: #{inspect(MapSet.to_list(unknown))}. " <>
          "Available: #{inspect(MapSet.to_list(available_names))}"
      )
    end

    # Filter to only declared + available tools
    filtered_tools =
      Enum.filter(all_tools, fn tool ->
        tool.name in declared_tool_names
      end)

    case filtered_tools do
      [] ->
        {[], nil}

      tools ->
        # Build a FRESH closure capturing session_context for this turn.
        resolver_fn = fn %LlmToolkit.Tool.Call{} = call ->
          resolver_mod.resolve(call, session_context)
        end

        {tools, resolver_fn}
    end
  end
end
