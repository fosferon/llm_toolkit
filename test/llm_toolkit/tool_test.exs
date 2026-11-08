defmodule LlmToolkit.ToolTest do
  use ExUnit.Case, async: true

  alias LlmToolkit.Tool

  describe "new/1" do
    test "creates a valid tool from atom keys" do
      assert {:ok, tool} =
               Tool.new(%{
                 name: "search",
                 description: "Search the knowledge base",
                 parameters: %{"type" => "object"}
               })

      assert tool.name == "search"
      assert tool.description == "Search the knowledge base"
      assert tool.parameters == %{"type" => "object"}
      assert tool.metadata == %{}
    end

    test "creates a valid tool from string keys" do
      assert {:ok, tool} =
               Tool.new(%{
                 "name" => "ping",
                 "description" => "Ping",
                 "parameters" => %{"type" => "object"}
               })

      assert tool.name == "ping"
    end

    test "accepts optional metadata" do
      assert {:ok, tool} =
               Tool.new(%{
                 name: "t",
                 description: "d",
                 parameters: %{},
                 metadata: %{"version" => "1.0"}
               })

      assert tool.metadata == %{"version" => "1.0"}
    end

    test "returns error for missing required fields" do
      assert {:error, {:missing_keys, keys}} = Tool.new(%{name: "x"})
      assert "description" in keys
      assert "parameters" in keys
    end

    test "returns error for invalid name type" do
      assert {:error, {:invalid_field, :name, _}} =
               Tool.new(%{name: 123, description: "d", parameters: %{}})
    end

    test "returns error for invalid parameters type" do
      assert {:error, {:invalid_field, :parameters, _}} =
               Tool.new(%{name: "n", description: "d", parameters: "not a map"})
    end

    test "returns error for invalid metadata type" do
      assert {:error, {:invalid_field, :metadata, _}} =
               Tool.new(%{name: "n", description: "d", parameters: %{}, metadata: "bad"})
    end
  end

  describe "from_map/1" do
    test "creates tool from plain map (typically YAML-loaded)" do
      assert {:ok, tool} =
               Tool.from_map(%{
                 "name" => "yaml_tool",
                 "description" => "Loaded from YAML",
                 "parameters" => %{"type" => "object"}
               })

      assert tool.name == "yaml_tool"
    end
  end

  describe "struct" do
    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(Tool, name: "x")
      end
    end

    test "has default metadata" do
      tool = %Tool{name: "x", description: "d", parameters: %{}}
      assert tool.metadata == %{}
    end
  end
end
