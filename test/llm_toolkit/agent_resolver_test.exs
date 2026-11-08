defmodule LlmToolkit.AgentResolverTest do
  use ExUnit.Case, async: true

  alias LlmToolkit.Tool
  alias LlmToolkit.Tool.Call

  # --- Test tool modules ------------------------------------------------------

  defmodule EchoTool do
    def definition do
      %Tool{
        name: "echo",
        description: "Echoes back the arguments",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "message" => %{"type" => "string"}
          }
        }
      }
    end

    def execute(args, _context) do
      {:ok, "Echo: #{args["message"]}"}
    end

    def sensitive_fields, do: ["message"]
  end

  defmodule ContextTool do
    def definition do
      %Tool{
        name: "context_probe",
        description: "Returns the context map",
        parameters: %{"type" => "object", "properties" => %{}},
        metadata: %{}
      }
    end

    def execute(_args, context) do
      {:ok, inspect(context)}
    end
  end

  defmodule RaisingTool do
    def definition do
      %Tool{
        name: "raising_tool",
        description: "Always raises",
        parameters: %{"type" => "object", "properties" => %{}},
        metadata: %{}
      }
    end

    def execute(_args, _context) do
      raise "intentional boom"
    end
  end

  defmodule NoSensitiveFieldsTool do
    def definition do
      %Tool{
        name: "no_sensitive",
        description: "No sensitive fields",
        parameters: %{"type" => "object", "properties" => %{}},
        metadata: %{}
      }
    end

    def execute(_args, _context) do
      {:ok, "ok"}
    end
  end

  defmodule TestResolver do
    use LlmToolkit.AgentResolver,
      tools: [EchoTool, ContextTool, RaisingTool, NoSensitiveFieldsTool]
  end

  # --- Tests ------------------------------------------------------------------

  describe "available_tools/0" do
    test "returns all tool definitions" do
      tools = TestResolver.available_tools()
      assert length(tools) == 4

      names = Enum.map(tools, & &1.name)
      assert "echo" in names
      assert "context_probe" in names
      assert "raising_tool" in names
      assert "no_sensitive" in names
    end

    test "returns Tool structs" do
      for tool <- TestResolver.available_tools() do
        assert %Tool{} = tool
        assert is_binary(tool.name)
        assert is_binary(tool.description)
        assert is_map(tool.parameters)
      end
    end
  end

  describe "resolve/1 (behaviour callback, no context)" do
    test "dispatches to the correct tool" do
      call = %Call{name: "echo", arguments: %{"message" => "hello"}}
      assert {:ok, "Echo: hello"} = TestResolver.resolve(call)
    end

    test "returns error for unknown tool" do
      call = %Call{name: "nonexistent", arguments: %{}}
      assert {:error, msg} = TestResolver.resolve(call)
      assert msg =~ "Unknown tool: nonexistent"
    end
  end

  describe "resolve/2 (with context)" do
    test "passes context through to the tool" do
      call = %Call{name: "context_probe", arguments: %{}}
      context = %{tenant_id: "t1", conversation_id: "c1"}

      assert {:ok, result} = TestResolver.resolve(call, context)
      assert result =~ "t1"
      assert result =~ "c1"
    end

    test "rescues raised exceptions and returns error tuple" do
      call = %Call{name: "raising_tool", arguments: %{}}

      assert {:error, msg} = TestResolver.resolve(call, %{})
      assert msg =~ "Tool execution failed"
      assert msg =~ "intentional boom"
    end
  end

  describe "sensitive_fields_for/1" do
    test "returns declared sensitive fields for a known tool" do
      assert TestResolver.sensitive_fields_for("echo") == ["message"]
    end

    test "returns empty list for tool without sensitive_fields/0" do
      assert TestResolver.sensitive_fields_for("no_sensitive") == []
    end

    test "returns empty list for unknown tool (graceful fallback)" do
      # Critical contract: unknown tool names must not crash telemetry
      # handlers. Better to emit un-redacted telemetry than break dispatch.
      assert TestResolver.sensitive_fields_for("no_such_tool") == []
      assert TestResolver.sensitive_fields_for("") == []
    end
  end

  describe "behaviour compliance" do
    test "implements LlmToolkit.ToolResolver" do
      behaviours =
        TestResolver.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert LlmToolkit.ToolResolver in behaviours
    end

    test "exports required callbacks" do
      assert function_exported?(TestResolver, :resolve, 1)
      assert function_exported?(TestResolver, :available_tools, 0)
    end
  end
end
