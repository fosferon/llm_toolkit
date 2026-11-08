defmodule LlmToolkit.Tool.Call do
  @moduledoc """
  Represents an LLM's request to invoke a tool.

  When a provider responds with one or more tool call requests, each is
  parsed into a `Call` struct by the provider codec.

  ## Fields

    * `id` - Provider-assigned call identifier (string or nil)
    * `name` - The tool name the LLM wants to invoke
    * `arguments` - Parsed argument map (always a map, never a JSON string)
  """

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t(),
          arguments: map()
        }

  @enforce_keys [:name, :arguments]
  defstruct [:id, :name, :arguments]

  @doc """
  Creates a new Call struct from a map of attributes.
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    name = get_field(attrs, :name)
    arguments = get_field(attrs, :arguments)
    id = get_field(attrs, :id)

    cond do
      is_nil(name) ->
        {:error, {:missing_keys, ["name"]}}

      is_nil(arguments) ->
        {:error, {:missing_keys, ["arguments"]}}

      not is_binary(name) ->
        {:error, {:invalid_field, :name, "must be a string"}}

      not is_map(arguments) ->
        {:error, {:invalid_field, :arguments, "must be a map"}}

      true ->
        {:ok, %__MODULE__{id: id, name: name, arguments: arguments}}
    end
  end

  defp get_field(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
