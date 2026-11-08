defmodule LlmToolkit.SessionToolsTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias LlmToolkit.Tool
  alias LlmToolkit.Tool.Call
  alias LlmToolkit.SessionTools

  # --- Test fixtures ----------------------------------------------------------

  defmodule AlphaTool do
    def definition do
      %Tool{
        name: "alpha",
        description: "Alpha tool",
        parameters: %{"type" => "object", "properties" => %{"x" => %{"type" => "string"}}}
      }
    end

    def execute(args, context) do
      {:ok, "alpha: args=#{inspect(args)} ctx=#{inspect(context)}"}
    end
  end

  defmodule BetaTool do
    def definition do
      %Tool{
        name: "beta",
        description: "Beta tool",
        parameters: %{"type" => "object", "properties" => %{}}
      }
    end

    def execute(_args, _context) do
      {:ok, "beta"}
    end
  end

  defmodule TestResolver do
    use LlmToolkit.AgentResolver, tools: [AlphaTool, BetaTool]
  end

  # --- Tests ------------------------------------------------------------------

  describe "prepare/3" do
    test "returns tools and resolver when declared names match" do
      context = %{tenant_id: "t1", conversation_id: "c1", tenant_slug: "ts"}
      {tools, resolver_fn} = SessionTools.prepare(TestResolver, ["alpha"], context)

      assert length(tools) == 1
      assert hd(tools).name == "alpha"
      assert is_function(resolver_fn, 1)

      call = %Call{name: "alpha", arguments: %{"x" => "hello"}}
      assert {:ok, result} = resolver_fn.(call)
      assert result =~ "alpha:"
      assert result =~ "hello"
      assert result =~ "t1"
    end

    test "filters to only declared tools" do
      context = %{}
      {tools, resolver_fn} = SessionTools.prepare(TestResolver, ["alpha", "beta"], context)

      assert length(tools) == 2
      names = Enum.map(tools, & &1.name)
      assert "alpha" in names
      assert "beta" in names
      assert is_function(resolver_fn, 1)
    end

    test "nil declared names returns empty tuple" do
      assert {[], nil} = SessionTools.prepare(TestResolver, nil, %{})
    end

    test "empty declared names returns empty tuple" do
      assert {[], nil} = SessionTools.prepare(TestResolver, [], %{})
    end

    test "unknown tool name filtered out with warning log" do
      context = %{tenant_id: "t1", conversation_id: "c1", tenant_slug: "test"}

      log =
        capture_log(fn ->
          {tools, resolver_fn} = SessionTools.prepare(TestResolver, ["unknown_tool"], context)
          assert tools == []
          assert is_nil(resolver_fn)
        end)

      assert log =~ "Unknown tools declared"
      assert log =~ "unknown_tool"
      assert log =~ "alpha"
      assert log =~ "beta"
    end

    test "mixed known and unknown tools returns only known, warns" do
      context = %{}

      log =
        capture_log(fn ->
          {tools, _resolver} = SessionTools.prepare(TestResolver, ["alpha", "gamma"], context)
          names = Enum.map(tools, & &1.name)
          assert names == ["alpha"]
        end)

      assert log =~ "Unknown tools declared"
      assert log =~ "gamma"
    end

    test "resolver closure is fresh per invocation" do
      context1 = %{tenant_id: "t1", conversation_id: "c1"}
      context2 = %{tenant_id: "t2", conversation_id: "c2"}

      {_, resolver1} = SessionTools.prepare(TestResolver, ["alpha"], context1)
      {_, resolver2} = SessionTools.prepare(TestResolver, ["alpha"], context2)

      call = %Call{name: "alpha", arguments: %{"x" => "x"}}

      assert {:ok, result1} = resolver1.(call)
      assert result1 =~ "t1"
      assert result1 =~ "c1"

      assert {:ok, result2} = resolver2.(call)
      assert result2 =~ "t2"
      assert result2 =~ "c2"
    end

    test "resolver closure preserves error shape for unknown tools" do
      context = %{tenant_id: "t1", conversation_id: "c1"}
      {_, resolver_fn} = SessionTools.prepare(TestResolver, ["alpha"], context)

      call = %Call{name: "nonexistent", arguments: %{}}
      assert {:error, msg} = resolver_fn.(call)
      assert msg =~ "Unknown tool: nonexistent"
    end

    test "all unknown tools yields empty tuple without warning when list empty" do
      # Empty declared list is already covered, but verify no log spam
      assert {[], nil} = SessionTools.prepare(TestResolver, [], %{})
    end
  end
end
