defmodule LlmToolkit.Tool.ResultTest do
  use ExUnit.Case, async: true

  alias LlmToolkit.Tool.Result

  describe "new/1" do
    test "creates a result with atom keys" do
      assert {:ok, result} = Result.new(%{name: "search", content: "found 3 items"})

      assert result.tool_call_id == nil
      assert result.name == "search"
      assert result.content == "found 3 items"
    end

    test "creates a result with string keys and tool_call_id" do
      assert {:ok, result} =
               Result.new(%{
                 "tool_call_id" => "call_abc",
                 "name" => "ping",
                 "content" => "pong"
               })

      assert result.tool_call_id == "call_abc"
      assert result.name == "ping"
    end

    test "returns error for missing name" do
      assert {:error, {:missing_keys, ["name"]}} = Result.new(%{content: "x"})
    end

    test "returns error for missing content" do
      assert {:error, {:missing_keys, ["content"]}} = Result.new(%{name: "x"})
    end

    test "returns error for invalid name type" do
      assert {:error, {:invalid_field, :name, _}} = Result.new(%{name: 42, content: "x"})
    end

    test "returns error for invalid content type" do
      assert {:error, {:invalid_field, :content, _}} = Result.new(%{name: "x", content: 123})
    end
  end

  describe "struct" do
    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(Result, name: "x")
      end
    end
  end
end
