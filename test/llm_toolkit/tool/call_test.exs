defmodule LlmToolkit.Tool.CallTest do
  use ExUnit.Case, async: true

  alias LlmToolkit.Tool.Call

  describe "new/1" do
    test "creates a call with atom keys" do
      assert {:ok, call} = Call.new(%{name: "search", arguments: %{"query" => "elixir"}})

      assert call.id == nil
      assert call.name == "search"
      assert call.arguments == %{"query" => "elixir"}
    end

    test "creates a call with string keys" do
      assert {:ok, call} =
               Call.new(%{"id" => "call_1", "name" => "ping", "arguments" => %{}})

      assert call.id == "call_1"
      assert call.name == "ping"
    end

    test "returns error for missing name" do
      assert {:error, {:missing_keys, ["name"]}} = Call.new(%{arguments: %{}})
    end

    test "returns error for missing arguments" do
      assert {:error, {:missing_keys, ["arguments"]}} = Call.new(%{name: "x"})
    end

    test "returns error for invalid name type" do
      assert {:error, {:invalid_field, :name, _}} = Call.new(%{name: 42, arguments: %{}})
    end

    test "returns error for invalid arguments type" do
      assert {:error, {:invalid_field, :arguments, _}} = Call.new(%{name: "x", arguments: "bad"})
    end
  end

  describe "struct" do
    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(Call, name: "x")
      end
    end
  end
end
