defmodule LlmToolkit.ToolResolverTest do
  use ExUnit.Case, async: true

  alias LlmToolkit.ToolResolver
  alias LlmToolkit.Tool
  alias LlmToolkit.Tool.Call

  describe "behaviour enforcement" do
    test "modules implementing ToolResolver must export resolve/1" do
      callbacks = ToolResolver.behaviour_info(:callbacks)
      assert {:resolve, 1} in callbacks
    end

    test "modules implementing ToolResolver must export available_tools/0" do
      callbacks = ToolResolver.behaviour_info(:callbacks)
      assert {:available_tools, 0} in callbacks
    end

    test "dispatch_recipe/1 is optional" do
      optional = ToolResolver.behaviour_info(:optional_callbacks)
      assert {:dispatch_recipe, 1} in optional
    end
  end

  describe "CodeTools implements ToolResolver" do
    test "CodeTools is listed as implementing the behaviour" do
      # This will fail at compile time if CodeTools doesn't implement ToolResolver
      behaviours =
        LlmToolkit.CodeTools.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert ToolResolver in behaviours
    end

    test "CodeTools.resolve/1 returns ok or error tuples" do
      # Successful call
      call = %Call{name: "bash", arguments: %{"command" => "echo test"}}
      assert {:ok, _} = LlmToolkit.CodeTools.resolve(call)

      # Failed call
      call = %Call{name: "unknown_tool", arguments: %{}}
      assert {:error, _} = LlmToolkit.CodeTools.resolve(call)
    end

    test "CodeTools.available_tools/0 returns Tool structs" do
      tools = LlmToolkit.CodeTools.available_tools()

      assert is_list(tools)
      assert length(tools) >= 12

      for tool <- tools do
        assert %Tool{} = tool
        assert is_binary(tool.name)
        assert is_binary(tool.description)
        assert is_map(tool.parameters)
      end
    end
  end

  describe "resolve/1 contract" do
    test "returns {:ok, string} on success" do
      call = %Call{name: "bash", arguments: %{"command" => "echo ok"}}
      result = LlmToolkit.CodeTools.resolve(call)

      case result do
        {:ok, content} -> assert is_binary(content)
        {:error, _} -> flunk("Expected {:ok, _} but got {:error, _}")
      end
    end

    test "returns {:error, string} on failure" do
      call = %Call{name: "bash", arguments: %{"command" => ""}}
      result = LlmToolkit.CodeTools.resolve(call)

      case result do
        {:ok, _} -> flunk("Expected {:error, _} but got {:ok, _}")
        {:error, reason} -> assert is_binary(reason)
      end
    end
  end
end
