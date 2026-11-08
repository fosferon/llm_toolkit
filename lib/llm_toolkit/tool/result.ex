defmodule LlmToolkit.Tool.Result do
  @moduledoc """
  The result of executing a tool call.

  After the resolver executes a `LlmToolkit.Tool.Call`, the outcome is
  wrapped in a `Result` struct before being fed back to the LLM.

  ## Fields

    * `tool_call_id` - Matches the originating `Call.id` (string or nil)
    * `name` - The tool name that was executed
    * `content` - String content returned by the tool
  """

  @type t :: %__MODULE__{
          tool_call_id: String.t() | nil,
          name: String.t(),
          content: String.t()
        }

  @enforce_keys [:name, :content]
  defstruct [:tool_call_id, :name, :content]

  @doc """
  Creates a new Result struct from a map of attributes.
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    name = get_field(attrs, :name)
    content = get_field(attrs, :content)
    tool_call_id = get_field(attrs, :tool_call_id)

    cond do
      is_nil(name) ->
        {:error, {:missing_keys, ["name"]}}

      is_nil(content) ->
        {:error, {:missing_keys, ["content"]}}

      not is_binary(name) ->
        {:error, {:invalid_field, :name, "must be a string"}}

      not is_binary(content) ->
        {:error, {:invalid_field, :content, "must be a string"}}

      true ->
        {:ok, %__MODULE__{tool_call_id: tool_call_id, name: name, content: content}}
    end
  end

  defp get_field(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
