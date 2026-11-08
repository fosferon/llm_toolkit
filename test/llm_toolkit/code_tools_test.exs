defmodule LlmToolkit.CodeToolsTest do
  use ExUnit.Case, async: true

  alias LlmToolkit.Tool.Call
  alias LlmToolkit.CodeTools

  @tmp_key {__MODULE__, :tmp_dir}

  setup_all do
    tmp_dir = Path.join(System.tmp_dir!(), "llm_toolkit_test_#{unique_suffix()}")

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

  # ── ToolResolver behaviour ────────────────────────────────

  describe "available_tools/0" do
    test "returns list of LlmToolkit.Tool structs" do
      tools = CodeTools.available_tools()

      assert is_list(tools)
      assert length(tools) >= 12

      names = Enum.map(tools, & &1.name) |> Enum.sort()

      assert "append_to_file" in names
      assert "bash" in names
      assert "edit_file" in names
      assert "file_info" in names
      assert "glob" in names
      assert "grep" in names
      assert "http_get" in names
      assert "list_directory" in names
      assert "multi_edit" in names
      assert "read_file" in names
      assert "tree" in names
      assert "write_file" in names
    end

    test "each tool has name, description, and parameters" do
      for tool <- CodeTools.available_tools() do
        assert is_binary(tool.name)
        assert is_binary(tool.description)
        assert is_map(tool.parameters)
        assert tool.parameters["type"] == "object"
      end
    end
  end

  describe "resolve/1 — unknown tool" do
    test "returns error for unknown tool name" do
      call = %Call{name: "fly_to_moon", arguments: %{}}
      assert {:error, msg} = CodeTools.resolve(call)
      assert msg =~ "Unknown tool"
    end
  end

  describe "resolve/2 — unknown tool with cwd" do
    test "returns error for unknown tool name via resolve/2" do
      call = %Call{name: "unknown", arguments: %{}}
      assert {:error, msg} = CodeTools.resolve(call, tmp_dir())
      assert msg =~ "Unknown tool"
    end
  end

  # ── read_file ──────────────────────────────────────────────

  describe "read_file" do
    test "reads file content" do
      path = Path.join(tmp_dir(), "read_test.txt")
      File.write!(path, "hello world\nline 2\nline 3")

      call = %Call{name: "read_file", arguments: %{"path" => path}}
      assert {:ok, output} = CodeTools.resolve(call)
      assert output =~ "hello world"
      assert output =~ "line 2"
    end

    test "respects offset and limit" do
      path = Path.join(tmp_dir(), "read_offset.txt")

      lines = Enum.map(1..10, &"line_#{&1}")
      File.write!(path, Enum.join(lines, "\n"))

      call = %Call{name: "read_file", arguments: %{"path" => path, "offset" => 3, "limit" => 2}}
      assert {:ok, output} = CodeTools.resolve(call)
      assert output =~ "line_3"
      assert output =~ "line_4"
      refute output =~ "line_2"
      refute output =~ "line_5"
    end

    test "returns error for missing file" do
      call = %Call{name: "read_file", arguments: %{"path" => "/nonexistent/file.txt"}}
      assert {:error, msg} = CodeTools.resolve(call)
      assert msg =~ "Cannot read"
    end

    test "resolves relative path against cwd" do
      File.write!(Path.join(tmp_dir(), "relative.txt"), "relative content")

      call = %Call{name: "read_file", arguments: %{"path" => "relative.txt"}}
      assert {:ok, output} = CodeTools.resolve(call, tmp_dir())
      assert output =~ "relative content"
    end
  end

  # ── write_file ─────────────────────────────────────────────

  describe "write_file" do
    test "writes content to file" do
      path = Path.join(tmp_dir(), "write_test.txt")

      call = %Call{name: "write_file", arguments: %{"path" => path, "content" => "new content"}}
      assert {:ok, msg} = CodeTools.resolve(call)
      assert msg =~ "Written"
      assert File.read!(path) == "new content"
    end

    test "creates parent directories" do
      path = Path.join(tmp_dir(), "deep/nested/dir/file.txt")

      call = %Call{name: "write_file", arguments: %{"path" => path, "content" => "deep"}}
      assert {:ok, _} = CodeTools.resolve(call)
      assert File.read!(path) == "deep"
    end

    test "overwrites existing file" do
      path = Path.join(tmp_dir(), "overwrite.txt")
      File.write!(path, "old")

      call = %Call{name: "write_file", arguments: %{"path" => path, "content" => "new"}}
      assert {:ok, _} = CodeTools.resolve(call)
      assert File.read!(path) == "new"
    end

    test "writes empty content" do
      path = Path.join(tmp_dir(), "empty.txt")

      call = %Call{name: "write_file", arguments: %{"path" => path, "content" => ""}}
      assert {:ok, _} = CodeTools.resolve(call)
      assert File.read!(path) == ""
    end
  end

  # ── edit_file ──────────────────────────────────────────────

  describe "edit_file" do
    test "replaces exact unique match" do
      path = Path.join(tmp_dir(), "edit_exact.txt")
      File.write!(path, "line 1\nline 2\nline 3")

      call = %Call{
        name: "edit_file",
        arguments: %{"path" => path, "oldText" => "line 2", "newText" => "LINE TWO"}
      }

      assert {:ok, msg} = CodeTools.resolve(call)
      assert msg =~ "Edited"
      assert File.read!(path) == "line 1\nLINE TWO\nline 3"
    end

    test "replaces multi-line block" do
      path = Path.join(tmp_dir(), "edit_multi.txt")
      File.write!(path, "before\nold line 1\nold line 2\nafter")

      call = %Call{
        name: "edit_file",
        arguments: %{
          "path" => path,
          "oldText" => "old line 1\nold line 2",
          "newText" => "new line 1\nnew line 2\nnew line 3"
        }
      }

      assert {:ok, _} = CodeTools.resolve(call)
      assert File.read!(path) == "before\nnew line 1\nnew line 2\nnew line 3\nafter"
    end

    test "rejects when oldText not found" do
      path = Path.join(tmp_dir(), "edit_missing.txt")
      File.write!(path, "line 1\nline 2")

      call = %Call{
        name: "edit_file",
        arguments: %{"path" => path, "oldText" => "not here", "newText" => "replacement"}
      }

      assert {:error, msg} = CodeTools.resolve(call)
      assert msg =~ "not found"
      assert File.read!(path) == "line 1\nline 2"
    end

    test "rejects when oldText matches multiple locations" do
      path = Path.join(tmp_dir(), "edit_ambiguous.txt")
      File.write!(path, "dup\nsomething\ndup")

      call = %Call{
        name: "edit_file",
        arguments: %{"path" => path, "oldText" => "dup", "newText" => "unique"}
      }

      assert {:error, msg} = CodeTools.resolve(call)
      assert msg =~ "matches 2 locations"
      assert msg =~ "must be unique"
      assert File.read!(path) == "dup\nsomething\ndup"
    end

    test "handles CRLF normalization" do
      path = Path.join(tmp_dir(), "edit_crlf.txt")
      File.write!(path, "line 1\r\nline 2\r\nline 3")

      call = %Call{
        name: "edit_file",
        arguments: %{"path" => path, "oldText" => "line 2", "newText" => "replaced"}
      }

      assert {:ok, _} = CodeTools.resolve(call)
      content = File.read!(path)
      assert content =~ "replaced"
      refute content =~ "line 2"
    end

    test "returns error for missing file" do
      call = %Call{
        name: "edit_file",
        arguments: %{
          "path" => "/nonexistent/edit.txt",
          "oldText" => "x",
          "newText" => "y"
        }
      }

      assert {:error, msg} = CodeTools.resolve(call)
      assert msg =~ "not found"
    end

    test "gives hint when first line matches but block doesn't" do
      path = Path.join(tmp_dir(), "edit_hint.txt")
      File.write!(path, "def foo do\n  :ok\nend")

      call = %Call{
        name: "edit_file",
        arguments: %{
          "path" => path,
          "oldText" => "def foo do\n  different content\nend",
          "newText" => "replaced"
        }
      }

      assert {:error, msg} = CodeTools.resolve(call)
      assert msg =~ "First line matches"
    end

    test "requires oldText and newText" do
      path = Path.join(tmp_dir(), "edit_required.txt")
      File.write!(path, "content")

      call = %Call{
        name: "edit_file",
        arguments: %{"path" => path, "newText" => "y"}
      }

      assert {:error, msg} = CodeTools.resolve(call)
      assert msg =~ "oldText"
    end
  end

  # ── multi_edit ─────────────────────────────────────────────

  describe "multi_edit" do
    test "applies multiple disjoint edits in one call" do
      path = Path.join(tmp_dir(), "multi_edit_basic.txt")
      File.write!(path, "alpha\nbeta\ngamma\ndelta")

      call = %Call{
        name: "multi_edit",
        arguments: %{
          "path" => path,
          "edits" => [
            %{"oldText" => "alpha", "newText" => "ALPHA"},
            %{"oldText" => "gamma", "newText" => "GAMMA"}
          ]
        }
      }

      assert {:ok, msg} = CodeTools.resolve(call)
      assert msg =~ "2 edits"
      assert File.read!(path) == "ALPHA\nbeta\nGAMMA\ndelta"
    end

    test "applies edits sequentially — each sees the result of the previous" do
      path = Path.join(tmp_dir(), "multi_edit_seq.txt")
      File.write!(path, "old line")

      call = %Call{
        name: "multi_edit",
        arguments: %{
          "path" => path,
          "edits" => [
            %{"oldText" => "old line", "newText" => "intermediate"},
            %{"oldText" => "intermediate", "newText" => "final"}
          ]
        }
      }

      assert {:ok, _} = CodeTools.resolve(call)
      assert File.read!(path) == "final"
    end

    test "rolls back all edits if any fails" do
      path = Path.join(tmp_dir(), "multi_edit_rollback.txt")
      original = "keep this\nchange this"
      File.write!(path, original)

      call = %Call{
        name: "multi_edit",
        arguments: %{
          "path" => path,
          "edits" => [
            %{"oldText" => "change this", "newText" => "CHANGED"},
            %{"oldText" => "not in file", "newText" => "FAIL"}
          ]
        }
      }

      assert {:error, msg} = CodeTools.resolve(call)
      assert msg =~ "not found"
      # First edit was rolled back — file unchanged
      assert File.read!(path) == original
    end

    test "rejects ambiguous edit within the batch" do
      path = Path.join(tmp_dir(), "multi_edit_ambig.txt")
      File.write!(path, "dup\ndup\nother")

      call = %Call{
        name: "multi_edit",
        arguments: %{
          "path" => path,
          "edits" => [
            %{"oldText" => "dup", "newText" => "ONE"}
          ]
        }
      }

      assert {:error, msg} = CodeTools.resolve(call)
      assert msg =~ "matches 2 locations"
      assert File.read!(path) == "dup\ndup\nother"
    end

    test "returns error for missing file" do
      call = %Call{
        name: "multi_edit",
        arguments: %{
          "path" => "/nonexistent/multi.txt",
          "edits" => [%{"oldText" => "x", "newText" => "y"}]
        }
      }

      assert {:error, msg} = CodeTools.resolve(call)
      assert msg =~ "not found"
    end

    test "validates edits array is present and non-empty" do
      path = Path.join(tmp_dir(), "multi_edit_empty.txt")
      File.write!(path, "content")

      call = %Call{
        name: "multi_edit",
        arguments: %{"path" => path, "edits" => []}
      }

      assert {:error, msg} = CodeTools.resolve(call)
      assert msg =~ "non-empty"
    end
  end

  # ── append_to_file ─────────────────────────────────────────

  describe "append_to_file" do
    test "appends content to existing file" do
      path = Path.join(tmp_dir(), "append_existing.txt")
      File.write!(path, "first\n")

      call = %Call{name: "append_to_file", arguments: %{"path" => path, "content" => "second\n"}}
      assert {:ok, msg} = CodeTools.resolve(call)
      assert msg =~ "Appended"
      assert File.read!(path) == "first\nsecond\n"
    end

    test "creates file if it doesn't exist" do
      path = Path.join(tmp_dir(), "append_new.txt")

      call = %Call{name: "append_to_file", arguments: %{"path" => path, "content" => "created\n"}}
      assert {:ok, msg} = CodeTools.resolve(call)
      assert msg =~ "Appended"
      assert File.read!(path) == "created\n"
    end

    test "creates parent directories" do
      path = Path.join(tmp_dir(), "append_deep/dir/file.txt")

      call = %Call{name: "append_to_file", arguments: %{"path" => path, "content" => "nested"}}
      assert {:ok, _} = CodeTools.resolve(call)
      assert File.read!(path) == "nested"
    end

    test "appends empty content (no-op but succeeds)" do
      path = Path.join(tmp_dir(), "append_empty.txt")
      File.write!(path, "existing")

      call = %Call{name: "append_to_file", arguments: %{"path" => path, "content" => ""}}
      assert {:ok, _msg} = CodeTools.resolve(call)
      assert File.read!(path) == "existing"
    end
  end

  # ── bash ───────────────────────────────────────────────────

  describe "bash" do
    test "executes command and returns output" do
      call = %Call{name: "bash", arguments: %{"command" => "echo hello"}}
      assert {:ok, output} = CodeTools.resolve(call)
      assert output =~ "hello"
    end

    test "returns error for non-zero exit code" do
      call = %Call{name: "bash", arguments: %{"command" => "exit 1"}}
      assert {:error, msg} = CodeTools.resolve(call)
      assert msg =~ "Exit code 1"
    end

    test "returns error for empty command" do
      call = %Call{name: "bash", arguments: %{"command" => ""}}
      assert {:error, msg} = CodeTools.resolve(call)
      assert msg =~ "non-empty"
    end

    test "returns error for nil command" do
      call = %Call{name: "bash", arguments: %{}}
      assert {:error, msg} = CodeTools.resolve(call)
      assert msg =~ "non-empty"
    end

    test "uses cwd for command execution" do
      File.write!(Path.join(tmp_dir(), "bash_test.txt"), "from cwd")

      call = %Call{name: "bash", arguments: %{"command" => "cat bash_test.txt"}}
      assert {:ok, output} = CodeTools.resolve(call, tmp_dir())
      assert output =~ "from cwd"
    end
  end

  # ── grep ───────────────────────────────────────────────────

  describe "grep" do
    test "finds matching lines" do
      path = Path.join(tmp_dir(), "grep_test.txt")
      File.write!(path, "apple\nbanana\ncherry\napple pie")

      call = %Call{name: "grep", arguments: %{"pattern" => "apple", "path" => path}}
      assert {:ok, output} = CodeTools.resolve(call)
      assert output =~ "apple"
      assert output =~ "apple pie"
    end

    test "returns no matches message when pattern not found" do
      path = Path.join(tmp_dir(), "grep_empty.txt")
      File.write!(path, "nothing relevant")

      call = %Call{name: "grep", arguments: %{"pattern" => "xyznotfound", "path" => path}}
      assert {:ok, msg} = CodeTools.resolve(call)
      assert msg =~ "No matches"
    end

    test "returns error for empty pattern" do
      call = %Call{name: "grep", arguments: %{"pattern" => ""}}
      assert {:error, msg} = CodeTools.resolve(call)
      assert msg =~ "non-empty pattern"
    end

    test "supports file_type filter" do
      File.write!(Path.join(tmp_dir(), "grep_ft.ex"), "defmodule Foo do\nend")
      File.write!(Path.join(tmp_dir(), "grep_ft.txt"), "defmodule Bar")

      call = %Call{
        name: "grep",
        arguments: %{"pattern" => "defmodule", "path" => tmp_dir(), "file_type" => "ex"}
      }

      assert {:ok, output} = CodeTools.resolve(call)
      assert output =~ "Foo"
      refute output =~ "Bar"
    end
  end

  # ── glob ───────────────────────────────────────────────────

  describe "glob" do
    test "finds files matching a pattern" do
      File.write!(Path.join(tmp_dir(), "app.ex"), "code")
      File.write!(Path.join(tmp_dir(), "app_test.ex"), "test")
      File.write!(Path.join(tmp_dir(), "app.md"), "docs")

      call = %Call{name: "glob", arguments: %{"pattern" => "**/*.ex", "path" => tmp_dir()}}
      assert {:ok, output} = CodeTools.resolve(call)
      assert output =~ "app.ex"
      assert output =~ "app_test.ex"
      refute output =~ "app.md"
    end

    test "finds files in subdirectories" do
      sub = Path.join(tmp_dir(), "glob_sub")
      File.mkdir_p!(sub)
      File.write!(Path.join(sub, "deep.txt"), "found me")

      call = %Call{name: "glob", arguments: %{"pattern" => "**/*.txt", "path" => tmp_dir()}}
      assert {:ok, output} = CodeTools.resolve(call)
      assert output =~ "deep.txt"
    end

    test "returns message when no files match" do
      call = %Call{
        name: "glob",
        arguments: %{"pattern" => "*.xyz_not_found", "path" => tmp_dir()}
      }

      assert {:ok, msg} = CodeTools.resolve(call)
      assert msg =~ "No files found"
    end

    test "returns error for missing pattern" do
      call = %Call{name: "glob", arguments: %{}}
      assert {:error, msg} = CodeTools.resolve(call)
      assert msg =~ "pattern"
    end
  end

  # ── list_directory ─────────────────────────────────────────

  describe "list_directory" do
    test "lists directory contents" do
      File.write!(Path.join(tmp_dir(), "file1.txt"), "a")
      File.write!(Path.join(tmp_dir(), "file2.txt"), "b")

      call = %Call{name: "list_directory", arguments: %{"path" => tmp_dir()}}
      assert {:ok, output} = CodeTools.resolve(call)
      assert output =~ "file1.txt"
      assert output =~ "file2.txt"
    end

    test "lists recursively" do
      subdir = Path.join(tmp_dir(), "subdir")
      File.mkdir_p!(subdir)
      File.write!(Path.join(subdir, "nested.txt"), "nested")

      call = %Call{name: "list_directory", arguments: %{"path" => tmp_dir(), "recursive" => true}}
      assert {:ok, output} = CodeTools.resolve(call)
      assert output =~ "nested.txt"
    end
  end

  # ── tree ───────────────────────────────────────────────────

  describe "tree" do
    test "shows directory tree structure" do
      File.mkdir_p!(Path.join(tmp_dir(), "tree_test/lib"))
      File.mkdir_p!(Path.join(tmp_dir(), "tree_test/test"))
      File.write!(Path.join(tmp_dir(), "tree_test/mix.exs"), "mix")
      File.write!(Path.join(tmp_dir(), "tree_test/lib/app.ex"), "app")
      File.write!(Path.join(tmp_dir(), "tree_test/test/app_test.exs"), "test")

      call = %Call{name: "tree", arguments: %{"path" => Path.join(tmp_dir(), "tree_test")}}
      assert {:ok, output} = CodeTools.resolve(call)
      assert output =~ "mix.exs"
      assert output =~ "lib"
      assert output =~ "app.ex"
      assert output =~ "test"
    end

    test "respects depth limit" do
      File.mkdir_p!(Path.join(tmp_dir(), "tree_deep/a/b/c"))
      File.write!(Path.join(tmp_dir(), "tree_deep/a/b/c/deep.txt"), "deep")

      call = %Call{
        name: "tree",
        arguments: %{"path" => Path.join(tmp_dir(), "tree_deep"), "max_depth" => 2}
      }

      assert {:ok, output} = CodeTools.resolve(call)
      assert output =~ "a"
      assert output =~ "b"
      refute output =~ "deep.txt"
    end

    test "shows file sizes" do
      File.mkdir_p!(Path.join(tmp_dir(), "tree_sizes"))
      File.write!(Path.join(tmp_dir(), "tree_sizes/small.txt"), "hi")
      File.write!(Path.join(tmp_dir(), "tree_sizes/big.txt"), String.duplicate("x", 1000))

      call = %Call{name: "tree", arguments: %{"path" => Path.join(tmp_dir(), "tree_sizes")}}
      assert {:ok, output} = CodeTools.resolve(call)
      assert output =~ "small.txt"
      assert output =~ "big.txt"
    end

    test "returns error for nonexistent path" do
      call = %Call{name: "tree", arguments: %{"path" => "/nonexistent/tree_path"}}
      assert {:error, msg} = CodeTools.resolve(call)
      assert msg =~ "Not a directory"
    end
  end

  # ── file_info ──────────────────────────────────────────────

  describe "file_info" do
    test "returns file metadata" do
      path = Path.join(tmp_dir(), "info_test.txt")
      File.write!(path, "hello world")

      call = %Call{name: "file_info", arguments: %{"path" => path}}
      assert {:ok, output} = CodeTools.resolve(call)
      assert output =~ "info_test.txt"
      assert output =~ "regular"
      assert output =~ "bytes"
    end

    test "shows directory type" do
      File.mkdir_p!(Path.join(tmp_dir(), "info_dir"))

      call = %Call{name: "file_info", arguments: %{"path" => Path.join(tmp_dir(), "info_dir")}}
      assert {:ok, output} = CodeTools.resolve(call)
      assert output =~ "directory"
    end

    test "returns error for missing file" do
      call = %Call{name: "file_info", arguments: %{"path" => "/nonexistent/info.txt"}}
      assert {:error, msg} = CodeTools.resolve(call)
      assert msg =~ "not found" or msg =~ "Cannot"
    end
  end

  # ── http_get ───────────────────────────────────────────────

  describe "http_get" do
    @tag :network
    test "fetches a URL and returns body" do
      call = %Call{name: "http_get", arguments: %{"url" => "https://httpbin.org/get"}}
      assert {:ok, output} = CodeTools.resolve(call)
      assert output =~ "httpbin.org"
    end

    test "returns error for missing URL" do
      call = %Call{name: "http_get", arguments: %{}}
      assert {:error, msg} = CodeTools.resolve(call)
      assert msg =~ "url"
    end

    test "returns error for unreachable URL" do
      call = %Call{
        name: "http_get",
        arguments: %{"url" => "http://localhost:1/nonexistent", "timeout" => 1}
      }

      assert {:error, msg} = CodeTools.resolve(call)
      assert msg =~ "error" or msg =~ "failed" or msg =~ "refused"
    end

    @tag :network
    test "respects timeout" do
      call = %Call{
        name: "http_get",
        arguments: %{"url" => "https://httpbin.org/delay/5", "timeout" => 2}
      }

      assert {:error, msg} = CodeTools.resolve(call)
      assert msg =~ "timeout" or msg =~ "Timed out"
    end

    @tag :network
    test "shows response status for non-200" do
      call = %Call{name: "http_get", arguments: %{"url" => "https://httpbin.org/status/404"}}
      assert {:error, msg} = CodeTools.resolve(call)
      assert msg =~ "404"
    end
  end

  # ── resolve/2 with cwd ────────────────────────────────────

  describe "resolve/2 — cwd parameterization" do
    test "all tools accept cwd as second argument" do
      path = Path.join(tmp_dir(), "cwd_test.txt")
      File.write!(path, "cwd content")

      # read
      assert {:ok, _} =
               CodeTools.resolve(
                 %Call{name: "read_file", arguments: %{"path" => "cwd_test.txt"}},
                 tmp_dir()
               )

      # write
      assert {:ok, _} =
               CodeTools.resolve(
                 %Call{
                   name: "write_file",
                   arguments: %{"path" => "cwd_new.txt", "content" => "x"}
                 },
                 tmp_dir()
               )

      # bash
      assert {:ok, _} =
               CodeTools.resolve(%Call{name: "bash", arguments: %{"command" => "ls"}}, tmp_dir())

      # grep
      assert {:ok, _} =
               CodeTools.resolve(
                 %Call{
                   name: "grep",
                   arguments: %{"pattern" => "cwd_content", "path" => "cwd_test.txt"}
                 },
                 tmp_dir()
               )

      # list_directory
      assert {:ok, _} =
               CodeTools.resolve(
                 %Call{name: "list_directory", arguments: %{"path" => "."}},
                 tmp_dir()
               )

      # glob
      assert {:ok, _} =
               CodeTools.resolve(
                 %Call{name: "glob", arguments: %{"pattern" => "*.txt", "path" => "."}},
                 tmp_dir()
               )

      # file_info
      assert {:ok, _} =
               CodeTools.resolve(
                 %Call{name: "file_info", arguments: %{"path" => "cwd_test.txt"}},
                 tmp_dir()
               )

      # tree
      assert {:ok, _} =
               CodeTools.resolve(%Call{name: "tree", arguments: %{"path" => "."}}, tmp_dir())
    end
  end
end
