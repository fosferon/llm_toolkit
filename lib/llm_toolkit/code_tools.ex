defmodule LlmToolkit.CodeTools do
  @moduledoc """
  Base code tools implementing `LlmToolkit.ToolResolver`.

  Provides 12 tools every agentic consumer needs to interact with a
  filesystem, shell, and the web.

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

  ## Safety Model

  The edit_file tool uses exact string matching with uniqueness validation:
  oldText must match exactly once before any write occurs, so a missing or
  ambiguous match aborts the edit without touching the file.

  multi_edit extends this with transactional semantics: if any edit in the
  batch fails, all changes are rolled back. The file is never left in a
  partial state.

  ## Path Resolution

  All file paths are resolved relative to `cwd`. When called through
  `resolve/1` (the ToolResolver callback), cwd defaults to ".". When called
  through `resolve/2`, the caller provides the working directory.
  """

  @behaviour LlmToolkit.ToolResolver

  alias LlmToolkit.Tool
  alias LlmToolkit.Tool.Call

  @max_output_bytes 50_000
  @default_read_lines 2000
  @bash_default_timeout 120
  @http_default_timeout 30

  # ── Tool Definitions ───────────────────────────────────────

  @tools [
    %Tool{
      name: "read_file",
      description:
        "Read file contents. Returns text truncated at 50KB. Use offset/limit for large files.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "path" => %{
            "type" => "string",
            "description" => "File path (relative to cwd or absolute)"
          },
          "offset" => %{
            "type" => "integer",
            "description" => "Line to start from (1-indexed, default 1)"
          },
          "limit" => %{"type" => "integer", "description" => "Max lines to read (default 2000)"}
        },
        "required" => ["path"]
      }
    },
    %Tool{
      name: "write_file",
      description:
        "Write content to a file. Creates parent directories. Overwrites existing files.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "File path"},
          "content" => %{"type" => "string", "description" => "Full file content to write"}
        },
        "required" => ["path", "content"]
      }
    },
    %Tool{
      name: "edit_file",
      description:
        "Edit a file using exact string replacement. " <>
          "oldText must match exactly and uniquely in the file. " <>
          "No changes are made if oldText is not found or matches multiple locations.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "File path"},
          "oldText" => %{
            "type" => "string",
            "description" => "Exact text to find — must be unique in file"
          },
          "newText" => %{"type" => "string", "description" => "Replacement text"}
        },
        "required" => ["path", "oldText", "newText"]
      }
    },
    %Tool{
      name: "multi_edit",
      description:
        "Apply multiple edits to a file in one call. Each edit uses exact string matching. " <>
          "Edits are applied sequentially. If any edit fails, all changes are rolled back.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "File path"},
          "edits" => %{
            "type" => "array",
            "description" => "Array of {oldText, newText} edits to apply in order",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "oldText" => %{"type" => "string", "description" => "Exact text to find"},
                "newText" => %{"type" => "string", "description" => "Replacement text"}
              },
              "required" => ["oldText", "newText"]
            }
          }
        },
        "required" => ["path", "edits"]
      }
    },
    %Tool{
      name: "append_to_file",
      description:
        "Append content to a file. Creates the file (and parent dirs) if it doesn't exist.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "File path"},
          "content" => %{"type" => "string", "description" => "Content to append"}
        },
        "required" => ["path", "content"]
      }
    },
    %Tool{
      name: "bash",
      description:
        "Execute a bash command. Returns stdout and stderr combined. Timeout defaults to 120 seconds.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "command" => %{"type" => "string", "description" => "Bash command to execute"},
          "timeout" => %{"type" => "integer", "description" => "Timeout in seconds (default 120)"}
        },
        "required" => ["command"]
      }
    },
    %Tool{
      name: "grep",
      description:
        "Search file contents with ripgrep. Supports regex patterns. Returns matching lines with line numbers.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "pattern" => %{"type" => "string", "description" => "Search pattern (regex supported)"},
          "path" => %{
            "type" => "string",
            "description" => "Directory or file to search (default: cwd)"
          },
          "file_type" => %{
            "type" => "string",
            "description" => "File extension filter (e.g. 'ex', 'md')"
          },
          "max_results" => %{"type" => "integer", "description" => "Max results (default 50)"}
        },
        "required" => ["pattern"]
      }
    },
    %Tool{
      name: "glob",
      description: "Find files matching a name pattern. Supports **, *, and ? wildcards.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "pattern" => %{
            "type" => "string",
            "description" => "Glob pattern (e.g. '**/*.ex', 'lib/*.md')"
          },
          "path" => %{
            "type" => "string",
            "description" => "Directory to search in (default: cwd)"
          }
        },
        "required" => ["pattern"]
      }
    },
    %Tool{
      name: "list_directory",
      description: "List directory contents. Shows files and subdirectories.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "Directory path (default: cwd)"},
          "recursive" => %{
            "type" => "boolean",
            "description" => "List recursively (default: false)"
          }
        },
        "required" => []
      }
    },
    %Tool{
      name: "tree",
      description:
        "Show directory tree structure with file sizes. Useful for understanding project layout.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "Root directory (default: cwd)"},
          "max_depth" => %{"type" => "integer", "description" => "Maximum depth (default: 4)"}
        },
        "required" => []
      }
    },
    %Tool{
      name: "file_info",
      description:
        "Get file metadata: size, type (regular/directory/symlink), modification time.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "File or directory path"}
        },
        "required" => ["path"]
      }
    },
    %Tool{
      name: "http_get",
      description:
        "Fetch a URL via HTTP GET. Returns response body. Useful for fetching docs, APIs, web content.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "url" => %{"type" => "string", "description" => "URL to fetch"},
          "timeout" => %{"type" => "integer", "description" => "Timeout in seconds (default 30)"},
          "headers" => %{
            "type" => "object",
            "description" => "Optional HTTP headers"
          }
        },
        "required" => ["url"]
      }
    }
  ]

  @impl true
  def available_tools, do: @tools

  # ── Tool Resolution ────────────────────────────────────────

  @impl true
  def resolve(%Call{} = call) do
    resolve(call, ".")
  end

  @doc """
  Resolve and execute a tool call within the given working directory.

  The `cwd` parameter is the dispatch working directory. Falls back to "."
  if no cwd is provided (via `resolve/1`).
  """
  @spec resolve(Call.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def resolve(%Call{name: name, arguments: args}, cwd) do
    case name do
      "read_file" -> do_read(args, cwd)
      "write_file" -> do_write(args, cwd)
      "edit_file" -> do_edit(args, cwd)
      "multi_edit" -> do_multi_edit(args, cwd)
      "append_to_file" -> do_append(args, cwd)
      "bash" -> do_bash(args, cwd)
      "grep" -> do_grep(args, cwd)
      "glob" -> do_glob(args, cwd)
      "list_directory" -> do_list(args, cwd)
      "tree" -> do_tree(args, cwd)
      "file_info" -> do_file_info(args, cwd)
      "http_get" -> do_http_get(args)
      _ -> {:error, "Unknown tool: #{name}"}
    end
  end

  # ── read_file ──────────────────────────────────────────────

  defp do_read(args, cwd) do
    path = resolve_path(args["path"], cwd)
    offset = (args["offset"] || 1) - 1
    limit = args["limit"] || @default_read_lines

    case File.read(path) do
      {:ok, content} ->
        lines = String.split(content, "\n")

        selected =
          lines
          |> Enum.drop(offset)
          |> Enum.take(limit)

        total = length(lines)
        showing = length(selected)
        header = "[#{path}:#{offset + 1}-#{offset + showing} of #{total} lines]\n"
        {:ok, header <> Enum.join(selected, "\n")}

      {:error, reason} ->
        {:error, "Cannot read #{path}: #{inspect(reason)}"}
    end
  end

  # ── write_file ─────────────────────────────────────────────

  defp do_write(args, cwd) do
    path = resolve_path(args["path"], cwd)
    content = args["content"] || ""

    dir = Path.dirname(path)

    case File.mkdir_p(dir) do
      :ok ->
        case File.write(path, content) do
          :ok ->
            {:ok, "Written #{byte_size(content)} bytes to #{path}"}

          {:error, reason} ->
            {:error, "Cannot write #{path}: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Cannot create directory #{dir}: #{inspect(reason)}"}
    end
  end

  # ── edit_file ──────────────────────────────────────────────
  #
  # Safety model:
  #   1. Read file content
  #   2. Normalize line endings (CRLF → LF) for matching
  #   3. Count exact occurrences of oldText
  #   4. If 0 matches → error, no write
  #   5. If >1 matches → error, no write (ambiguous)
  #   6. If exactly 1 → perform replacement, write back

  defp do_edit(args, cwd) do
    path = resolve_path(args["path"], cwd)
    old_text = args["oldText"]
    new_text = args["newText"]

    if is_nil(old_text) or is_nil(new_text) do
      {:error, "edit_file requires oldText and newText"}
    else
      do_edit_file(path, old_text, new_text)
    end
  end

  defp do_edit_file(path, old_text, new_text) do
    case File.read(path) do
      {:ok, content} ->
        normalized = String.replace(content, "\r\n", "\n")
        old_normalized = String.replace(old_text, "\r\n", "\n")

        case apply_single_edit(path, normalized, old_normalized, new_text) do
          {:ok, _} = result -> result
          {:error, _} = error -> error
        end

      {:error, :enoent} ->
        {:error, "File not found: #{path}"}

      {:error, reason} ->
        {:error, "Cannot read #{path}: #{inspect(reason)}"}
    end
  end

  defp apply_single_edit(path, content, old_text, new_text) do
    count = count_occurrences(content, old_text)

    cond do
      count == 0 ->
        {:error, "oldText not found in #{path}. " <> hint_not_found(content, old_text)}

      count > 1 ->
        {:error,
         "oldText matches #{count} locations in #{path} — must be unique. " <>
           "Add more surrounding context to make it unique."}

      true ->
        updated = String.replace(content, old_text, new_text, global: false)

        case File.write(path, updated) do
          :ok ->
            lines_added = String.split(new_text, "\n") |> length()
            lines_removed = String.split(old_text, "\n") |> length()
            {:ok, "Edited #{path} (#{lines_removed} → #{lines_added} lines)"}

          {:error, reason} ->
            {:error, "Cannot write #{path}: #{inspect(reason)}"}
        end
    end
  end

  # ── multi_edit ─────────────────────────────────────────────
  #
  # Transactional semantics:
  #   1. Read file
  #   2. Apply edits sequentially in memory
  #   3. If any edit fails → return error, don't write
  #   4. If all succeed → write the final result

  defp do_multi_edit(args, cwd) do
    path = resolve_path(args["path"], cwd)
    edits = args["edits"]

    cond do
      is_nil(edits) or not is_list(edits) ->
        {:error, "multi_edit requires a non-empty 'edits' array"}

      edits == [] ->
        {:error, "multi_edit requires a non-empty 'edits' array"}

      true ->
        do_multi_edit_file(path, edits)
    end
  end

  defp do_multi_edit_file(path, edits) do
    case File.read(path) do
      {:ok, content} ->
        normalized = String.replace(content, "\r\n", "\n")

        case apply_edits_sequential(path, normalized, edits, 0) do
          {:ok, final_content, edit_count} ->
            case File.write(path, final_content) do
              :ok ->
                {:ok, "Applied #{edit_count} edits to #{path}"}

              {:error, reason} ->
                {:error, "Cannot write #{path}: #{inspect(reason)}"}
            end

          {:error, _} = error ->
            error
        end

      {:error, :enoent} ->
        {:error, "File not found: #{path}"}

      {:error, reason} ->
        {:error, "Cannot read #{path}: #{inspect(reason)}"}
    end
  end

  defp apply_edits_sequential(_path, content, [], count), do: {:ok, content, count}

  defp apply_edits_sequential(path, content, [edit | rest], count) do
    old_text = edit["oldText"]
    new_text = edit["newText"]

    if is_nil(old_text) or is_nil(new_text) do
      {:error, "Edit ##{count + 1} requires oldText and newText"}
    else
      old_normalized = String.replace(old_text, "\r\n", "\n")
      match_count = count_occurrences(content, old_normalized)

      cond do
        match_count == 0 ->
          {:error,
           "Edit ##{count + 1}: oldText not found in #{path}. " <>
             hint_not_found(content, old_normalized)}

        match_count > 1 ->
          {:error,
           "Edit ##{count + 1}: oldText matches #{match_count} locations in #{path} — must be unique."}

        true ->
          updated = String.replace(content, old_normalized, new_text, global: false)
          apply_edits_sequential(path, updated, rest, count + 1)
      end
    end
  end

  # ── append_to_file ─────────────────────────────────────────

  defp do_append(args, cwd) do
    path = resolve_path(args["path"], cwd)
    content = args["content"] || ""

    dir = Path.dirname(path)
    File.mkdir_p!(dir)

    case File.write(path, content, [:append]) do
      :ok ->
        {:ok, "Appended #{byte_size(content)} bytes to #{path}"}

      {:error, reason} ->
        {:error, "Cannot append to #{path}: #{inspect(reason)}"}
    end
  end

  # ── bash ───────────────────────────────────────────────────

  defp do_bash(args, cwd) do
    command = args["command"]
    timeout_sec = args["timeout"] || @bash_default_timeout
    timeout_ms = timeout_sec * 1000

    if is_nil(command) or command == "" do
      {:error, "bash requires a non-empty command"}
    else
      task =
        Task.async(fn ->
          System.cmd("bash", ["-c", command],
            stderr_to_stdout: true,
            cd: cwd
          )
        end)

      case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
        {:ok, {output, 0}} ->
          {:ok, truncate(output, @max_output_bytes)}

        {:ok, {output, code}} ->
          truncated = truncate(output, 10_000)
          {:error, "Exit code #{code}:\n#{truncated}"}

        nil ->
          {:error, "Command timed out after #{timeout_sec}s"}
      end
    end
  rescue
    e ->
      {:error, "bash execution error: #{Exception.message(e)}"}
  end

  # ── grep ───────────────────────────────────────────────────

  defp do_grep(args, cwd) do
    pattern = args["pattern"]
    search_path = resolve_path(args["path"] || ".", cwd)
    file_type = args["file_type"]
    max = args["max_results"] || 50

    if is_nil(pattern) or pattern == "" do
      {:error, "grep requires a non-empty pattern"}
    else
      rg_args =
        [
          "--color=never",
          "--line-number",
          "--max-count",
          to_string(max),
          "-e",
          pattern,
          search_path
        ]
        |> then(fn args ->
          if file_type do
            glob = "*.#{file_type}"
            ["--glob", glob | args]
          else
            args
          end
        end)

      case System.cmd("rg", rg_args, stderr_to_stdout: true, cd: cwd) do
        {output, 0} ->
          {:ok, truncate(output, @max_output_bytes)}

        {_output, 1} ->
          {:ok, "No matches found for: #{pattern}"}

        {output, code} ->
          {:error, "rg exit #{code}: #{truncate(output, 5_000)}"}
      end
    end
  rescue
    e ->
      {:error, "grep error: #{Exception.message(e)}"}
  end

  # ── glob ───────────────────────────────────────────────────

  defp do_glob(args, cwd) do
    pattern = args["pattern"]
    search_path = resolve_path(args["path"] || ".", cwd)

    if is_nil(pattern) or pattern == "" do
      {:error, "glob requires a pattern"}
    else
      matches =
        Path.wildcard(Path.join(search_path, pattern))
        |> Enum.filter(&File.exists?/1)
        |> Enum.take(200)

      case matches do
        [] ->
          {:ok, "No files found matching: #{pattern}"}

        _ ->
          # Show relative to search_path when possible
          output =
            Enum.map(matches, fn m ->
              rel = Path.relative_to(m, search_path)
              if rel == m, do: m, else: rel
            end)
            |> Enum.join("\n")

          {:ok, "#{length(matches)} files:\n#{output}"}
      end
    end
  end

  # ── list_directory ─────────────────────────────────────────

  defp do_list(args, cwd) do
    path = resolve_path(args["path"] || ".", cwd)
    recursive = args["recursive"] || false

    cmd =
      if recursive, do: "find '#{path}' -maxdepth 5 -type f | head -200", else: "ls -la '#{path}'"

    case System.cmd("bash", ["-c", cmd], stderr_to_stdout: true, cd: cwd) do
      {output, 0} -> {:ok, truncate(output, @max_output_bytes)}
      {output, _} -> {:error, truncate(output, 5_000)}
    end
  rescue
    e ->
      {:error, "list_directory error: #{Exception.message(e)}"}
  end

  # ── tree ───────────────────────────────────────────────────

  defp do_tree(args, cwd) do
    path = resolve_path(args["path"] || ".", cwd)
    max_depth = args["max_depth"] || 4

    unless File.dir?(path) do
      {:error, "Not a directory: #{path}"}
    else
      tree = build_tree(path, 0, max_depth)
      {:ok, tree}
    end
  end

  defp build_tree(path, depth, max_depth) when depth > max_depth do
    _ = path
    ""
  end

  defp build_tree(path, depth, max_depth) do
    prefix = String.duplicate("  ", depth)
    name = if depth == 0, do: path, else: Path.basename(path)

    case File.ls(path) do
      {:ok, entries} ->
        sorted = Enum.sort(entries)
        visible = Enum.reject(sorted, &String.starts_with?(&1, "."))

        {dirs, files} =
          visible
          |> Enum.map(fn e ->
            full = Path.join(path, e)

            case File.stat(full) do
              {:ok, %File.Stat{type: :directory}} ->
                {:dir, e, full}

              {:ok, %File.Stat{size: size}} ->
                {:file, e, size}

              _ ->
                nil
            end
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.split_with(fn {kind, _, _} -> kind == :dir end)

        file_lines =
          files
          |> Enum.map(fn {:file, e, size} ->
            "#{prefix}  #{e} (#{format_bytes(size)})"
          end)

        dir_lines =
          dirs
          |> Enum.flat_map(fn {:dir, e, full} ->
            sub = build_tree(full, depth + 1, max_depth)

            if sub == "" do
              ["#{prefix}  #{e}/"]
            else
              ["#{prefix}  #{e}/", sub]
            end
          end)

        total_files = length(files)
        total_dirs = length(dirs)

        header =
          if depth == 0 do
            "#{name}/ (#{total_dirs} dirs, #{total_files} files)\n"
          else
            ""
          end

        (header <> Enum.join(file_lines ++ dir_lines, "\n"))
        |> String.trim_trailing("\n")

      {:error, reason} ->
        "#{prefix}  [error: #{inspect(reason)}]"
    end
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes}B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{div(bytes, 1024)}KB"
  defp format_bytes(bytes), do: "#{div(bytes, 1024 * 1024)}MB"

  # ── file_info ──────────────────────────────────────────────

  defp do_file_info(args, cwd) do
    path = resolve_path(args["path"], cwd)

    case File.stat(path) do
      {:ok, %File.Stat{} = stat} ->
        lines = [
          "Path: #{path}",
          "Type: #{format_type(stat.type)}",
          "Size: #{format_bytes(stat.size)} (#{stat.size} bytes)",
          "Modified: #{format_time(stat.mtime)}",
          "Access: #{format_time(stat.atime)}",
          "Permissions: #{stat.mode}"
        ]

        {:ok, Enum.join(lines, "\n")}

      {:error, :enoent} ->
        {:error, "File not found: #{path}"}

      {:error, reason} ->
        {:error, "Cannot stat #{path}: #{inspect(reason)}"}
    end
  end

  defp format_type(:regular), do: "regular file"
  defp format_type(:directory), do: "directory"
  defp format_type(:symlink), do: "symlink"
  defp format_type(other), do: to_string(other)

  defp format_time({{year, month, day}, {hour, min, sec}}) do
    "#{year}-#{pad(month)}-#{pad(day)} #{pad(hour)}:#{pad(min)}:#{pad(sec)}"
  end

  defp format_time(erlang_time) when is_tuple(erlang_time), do: inspect(erlang_time)
  defp format_time(_), do: "unknown"

  defp pad(n) when n < 10, do: "0#{n}"
  defp pad(n), do: "#{n}"

  # ── http_get ───────────────────────────────────────────────

  defp do_http_get(args) do
    url = args["url"]
    timeout_sec = args["timeout"] || @http_default_timeout
    headers = args["headers"] || %{}
    timeout_ms = timeout_sec * 1000

    if is_nil(url) or url == "" do
      {:error, "http_get requires a url"}
    else
      req_opts = [
        url: url,
        method: :get,
        receive_timeout: timeout_ms,
        max_redirects: 5
      ]

      req_opts =
        if map_size(headers) > 0 do
          Keyword.put(req_opts, :headers, Map.to_list(headers))
        else
          req_opts
        end

      case Req.request(req_opts) do
        {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
          body_str = if is_binary(body), do: body, else: inspect(body)
          header = "[HTTP #{status} from #{url}]\n"
          {:ok, header <> truncate(body_str, @max_output_bytes)}

        {:ok, %Req.Response{status: status, body: body}} ->
          body_str = if is_binary(body), do: body, else: inspect(body)
          {:error, "HTTP #{status} from #{url}:\n#{truncate(body_str, 5_000)}"}

        {:error, %Req.TransportError{reason: reason}} ->
          {:error, "HTTP request failed: #{inspect(reason)}"}

        {:error, exception} ->
          {:error, "HTTP request failed: #{Exception.message(exception)}"}
      end
    end
  rescue
    e ->
      {:error, "http_get error: #{Exception.message(e)}"}
  end

  # ── Helpers ────────────────────────────────────────────────

  defp resolve_path(path, cwd) do
    if Path.type(path) == :absolute do
      path
    else
      Path.expand(path, cwd)
    end
  end

  defp count_occurrences(haystack, needle) do
    :binary.matches(haystack, needle) |> length()
  end

  defp hint_not_found(content, old_text) do
    first_line =
      old_text
      |> String.split("\n")
      |> List.first()

    if first_line && String.length(first_line) > 0 do
      if String.contains?(content, first_line) do
        "First line matches but the full block does not. Check indentation and whitespace."
      else
        "First line '#{String.slice(first_line, 0, 60)}' not found in file."
      end
    else
      "Check that the text exists in the file."
    end
  end

  defp truncate(text, max_bytes) when byte_size(text) <= max_bytes, do: text

  defp truncate(text, max_bytes) do
    text
    |> binary_part(0, max_bytes)
    |> String.slice(0..-2//1)
    |> Kernel.<>("\n... [truncated at #{max_bytes} bytes]")
  end
end
