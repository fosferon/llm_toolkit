# LlmToolkit

Base code tools for agentic LLM execution — a self-contained, composable tool framework for building AI agents in Elixir.

Provides 12 file/shell/web tools, a `ToolResolver` behaviour, composable resolver architecture, session-scoped tool filtering, and an Ecto trace schema for audit logging.

## Tools

| Tool | Purpose |
|---|---|
| `read_file` | Read file contents with offset/limit |
| `write_file` | Write or overwrite a file |
| `edit_file` | Exact-match single edit |
| `multi_edit` | Multiple edits in one call with rollback |
| `append_to_file` | Append content to a file |
| `bash` | Execute shell commands |
| `grep` | Search file contents (ripgrep) |
| `glob` | Find files by name pattern |
| `list_directory` | List directory contents |
| `tree` | Visual directory tree with sizes |
| `file_info` | File metadata (size, type, mtime) |
| `http_get` | Fetch a URL |

The three `http_get` tests that call httpbin.org are tagged `:network` and excluded by default; `test_helper.exs` runs them when `LLM_TOOLKIT_NETWORK_TESTS=1` (or `true`), and `mix test --include network` overrides the exclusion.

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:llm_toolkit, "~> 0.1.1"}
  ]
end
```

## Usage

### Standalone

```elixir
alias LlmToolkit.CodeTools
alias LlmToolkit.Tool.Call

# Use with default cwd (".")
{:ok, content} = CodeTools.resolve(%Call{name: "read_file", arguments: %{"path" => "README.md"}})

# Use with specific cwd
{:ok, content} = CodeTools.resolve(
  %Call{name: "read_file", arguments: %{"path" => "README.md"}},
  "/path/to/project"
)
```

### With Your Agent Loop

```elixir
# As the sole tool resolver
MyAgent.Loop.run(task, LlmToolkit.CodeTools, opts)

# Via resolver tuple (binds working directory)
MyAgent.Loop.run(task, {LlmToolkit.CodeTools, "/project"}, opts)
```

### Composed with Domain Tools

```elixir
# Base tools + your own tools
resolver = LlmToolkit.Composition.new([
  {LlmToolkit.CodeTools, "/project"},
  MyApp.DomainTools
])

tools = LlmToolkit.Composition.available_tools(resolver)
{:ok, result} = LlmToolkit.Composition.resolve(resolver, call)
```

### Configurable Resolver with `use AgentResolver`

```elixir
defmodule MyApp.Tools.Resolver do
  use LlmToolkit.AgentResolver, tools: [
    MyApp.Tools.Search,
    MyApp.Tools.Analyze
  ]
end

# Each tool module implements:
#   definition/0        → %LlmToolkit.Tool{}
#   execute/2           → (args, context) → {:ok, string} | {:error, string}
#   sensitive_fields/0  → ["api_key"]     (optional, for telemetry scrubbing)
```

### Session-Scoped Tool Filtering

```elixir
alias LlmToolkit.Tool.Call

# Prepare only the tools declared for a session turn
{tools, resolver_fn} = LlmToolkit.SessionTools.prepare(
  MyApp.Tools.Resolver,
  ["search", "analyze"],
  %{user_id: "abc", project: "/repo"}
)

# resolver_fn is a fresh closure — thread-safe, no process dictionary
{:ok, result} = resolver_fn.(%Call{name: "search", arguments: %{"query" => "elixir"}})
```

## Architecture

| Module | Role |
|---|---|
| `LlmToolkit.ToolResolver` | Behaviour — `resolve/1`, `available_tools/0`, optional `dispatch_recipe/1` |
| `LlmToolkit.Tool` | Provider-neutral tool definition (name, description, JSON Schema params) |
| `LlmToolkit.Tool.Call` | An LLM's request to invoke a tool |
| `LlmToolkit.Tool.Result` | The outcome of executing a tool call |
| `LlmToolkit.CodeTools` | The 12 base tools implementing `ToolResolver` |
| `LlmToolkit.AgentResolver` | `use`-based macro — list your tool modules, get a full resolver |
| `LlmToolkit.Composition` | Merge multiple resolvers into one (first match wins) |
| `LlmToolkit.SessionTools` | Filter tools by declaration, build context-bound closures |
| `LlmToolkit.Trace` | Ecto schema for audit logging tool invocations |

## Safety Model

**edit_file:** Uses exact string matching with uniqueness validation. `oldText` must match exactly once. No silent corruption.

**multi_edit:** Transactional — applies edits sequentially in memory. If any edit fails, the file is never written. All-or-nothing.

## Dependencies

- **Req** (~> 0.5) — HTTP client for the `http_get` tool
- **Ecto** (~> 3.12) — Schema/changesets for the `Trace` audit schema

Both are lightweight and runtime-only.

## Contributing

A non-fork copy of this repository must set the `PUBLIC_GUARD_EXTRA` secret, or the public guard fails closed in CI.

## Companion packages

Part of the fosferon Elixir stack: [llm_core](https://github.com/fosferon/llm_core), [agent_engine](https://github.com/fosferon/agent_engine), [foresight](https://github.com/fosferon/foresight), [voice_engine](https://github.com/fosferon/voice_engine), [workflow_stem](https://github.com/fosferon/workflow_stem), and [bee](https://github.com/fosferon/bee).
