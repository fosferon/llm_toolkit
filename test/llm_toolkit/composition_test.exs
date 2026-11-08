defmodule LlmToolkit.CompositionTest do
  use ExUnit.Case, async: true

  alias LlmToolkit.Tool
  alias LlmToolkit.Tool.Call
  alias LlmToolkit.CodeTools
  alias LlmToolkit.Composition

  @tmp_key {__MODULE__, :tmp_dir}

  # A mock domain-specific resolver for testing composition
  defmodule DomainResolver do
    @behaviour LlmToolkit.ToolResolver

    @impl true
    def available_tools do
      [
        %Tool{
          name: "domain_search",
          description: "Search the domain",
          parameters: %{"type" => "object", "properties" => %{"q" => %{"type" => "string"}}}
        }
      ]
    end

    @impl true
    def resolve(%Call{name: "domain_search", arguments: %{"q" => query}}) do
      {:ok, "Results for: #{query}"}
    end

    def resolve(%Call{name: name}) do
      {:error, "Unknown tool: #{name}"}
    end
  end

  setup_all do
    tmp_dir = Path.join(System.tmp_dir!(), "llm_toolkit_comp_test_#{unique_suffix()}")

    File.mkdir_p!(tmp_dir)
    :persistent_term.put(@tmp_key, tmp_dir)

    on_exit(fn ->
      :persistent_term.erase(@tmp_key)
      File.rm_rf!(tmp_dir)
    end)

    :ok
  end

  defp tmp_dir, do: :persistent_term.get(@tmp_key)

  defp unique_suffix, do: Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

  describe "new/1" do
    test "accepts module specs" do
      comp = Composition.new([DomainResolver])
      assert %Composition{resolvers: [{DomainResolver, "."}]} = comp
    end

    test "accepts {module, cwd} tuples" do
      comp = Composition.new([{CodeTools, "/tmp"}])
      assert %Composition{resolvers: [{CodeTools, "/tmp"}]} = comp
    end

    test "accepts mixed specs" do
      comp = Composition.new([{CodeTools, "/tmp"}, DomainResolver])
      assert %Composition{resolvers: [{CodeTools, "/tmp"}, {DomainResolver, "."}]} = comp
    end
  end

  describe "available_tools/1" do
    test "merges tools from all resolvers" do
      comp = Composition.new([CodeTools, DomainResolver])
      tools = Composition.available_tools(comp)

      names = Enum.map(tools, & &1.name)
      assert "domain_search" in names
      assert "read_file" in names
      assert "bash" in names
    end

    test "returns base tools alone" do
      comp = Composition.new([CodeTools])
      tools = Composition.available_tools(comp)
      assert length(tools) == 12
    end

    test "returns domain tools alone" do
      comp = Composition.new([DomainResolver])
      tools = Composition.available_tools(comp)
      assert length(tools) == 1
    end
  end

  describe "resolve/2" do
    test "dispatches to base tools" do
      path = Path.join(tmp_dir(), "comp_test.txt")
      File.write!(path, "hello")

      comp = Composition.new([{CodeTools, tmp_dir()}])

      call = %Call{name: "read_file", arguments: %{"path" => "comp_test.txt"}}
      assert {:ok, output} = Composition.resolve(comp, call)
      assert output =~ "hello"
    end

    test "dispatches to domain tools" do
      comp = Composition.new([CodeTools, DomainResolver])

      call = %Call{name: "domain_search", arguments: %{"q" => "test"}}
      assert {:ok, output} = Composition.resolve(comp, call)
      assert output =~ "Results for: test"
    end

    test "returns error for unknown tool across all resolvers" do
      comp = Composition.new([CodeTools, DomainResolver])

      call = %Call{name: "fly_to_moon", arguments: %{}}
      assert {:error, msg} = Composition.resolve(comp, call)
      assert msg =~ "Unknown tool"
    end

    test "first resolver wins for overlapping tool names" do
      comp = Composition.new([DomainResolver, CodeTools])

      # domain_search is in DomainResolver, which is first
      call = %Call{name: "domain_search", arguments: %{"q" => "first wins"}}
      assert {:ok, output} = Composition.resolve(comp, call)
      assert output =~ "first wins"
    end

    test "falls through to next resolver if first doesn't know tool" do
      comp = Composition.new([DomainResolver, {CodeTools, tmp_dir()}])

      # read_file is not in DomainResolver, falls through to CodeTools
      path = Path.join(tmp_dir(), "fallback.txt")
      File.write!(path, "fallback content")

      call = %Call{name: "read_file", arguments: %{"path" => "fallback.txt"}}
      assert {:ok, output} = Composition.resolve(comp, call)
      assert output =~ "fallback content"
    end
  end

  describe "module loading" do
    test "honours the tuple cwd when the resolver module is not loaded" do
      mod = compile_unloaded_resolver()
      comp = Composition.new([{mod, tmp_dir()}])

      call = %Call{name: "anything", arguments: %{}}
      assert Composition.resolve(comp, call) == {:ok, tmp_dir()}
      assert :code.is_loaded(mod)
    end

    test "finds dispatch_recipe/1 when the resolver module is not loaded" do
      mod = compile_unloaded_resolver()
      comp = Composition.new([{mod, tmp_dir()}])

      recipe = Composition.dispatch_recipe(comp, "anything")
      assert is_function(recipe, 1)
      assert recipe.(%{}) == %{tool: "anything", source: :unloaded}
    end
  end

  describe "dispatch_recipe/2" do
    test "returns nil when no resolver has a recipe" do
      comp = Composition.new([CodeTools])
      assert nil == Composition.dispatch_recipe(comp, "read_file")
    end
  end

  # Compile a resolver into a beam on disk, then remove it from the code server.
  # Only Code.ensure_loaded?/1 can load it again, which pins the load-before-probe
  # behaviour deterministically (function_exported?/3 is false for unloaded modules).
  defp compile_unloaded_resolver do
    suffix = unique_suffix()
    mod = Module.concat(__MODULE__, "Unloaded#{suffix}")

    source = """
    defmodule #{inspect(mod)} do
      def available_tools, do: []
      def resolve(_call), do: {:error, "resolve/1 called"}
      def resolve(_call, cwd), do: {:ok, cwd}
      def dispatch_recipe(name), do: fn _ -> %{tool: name, source: :unloaded} end
    end
    """

    [{^mod, binary}] = Code.compile_string(source)
    ebin = Path.join(tmp_dir(), "ebin_#{suffix}")
    File.mkdir_p!(ebin)
    File.write!(Path.join(ebin, "#{mod}.beam"), binary)
    Code.prepend_path(ebin)

    on_exit(fn ->
      Code.delete_path(ebin)
      :code.purge(mod)
      :code.delete(mod)
    end)

    :code.purge(mod)
    :code.delete(mod)
    false = :code.is_loaded(mod)
    mod
  end
end
