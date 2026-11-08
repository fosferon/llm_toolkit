defmodule LlmToolkit.Trace do
  @moduledoc """
  Ecto schema for the `tool_traces` table.

  Records every tool invocation made by an agent during a conversation turn.
  Traces are immutable audit records — they support creation but not updates.

  The host application decides which database schema the `tool_traces` table
  belongs to. This schema module is storage-agnostic
  and can be used with any Ecto repo.

  ## Fields

    * `tenant_id` — opaque tenant identifier (binary UUID)
    * `conversation_id` — opaque conversation identifier (binary UUID)
    * `tool_name` — name of the invoked tool
    * `arguments` — argument map as provided by the LLM
    * `result` — result map (arbitrary shape determined by the tool)
    * `result_type` — `"ok"` or `"error"`
    * `duration_ms` — execution wall time in milliseconds
    * `iteration` — turn iteration counter (for multi-turn tool loops)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @result_types ~w(ok error)

  @derive {Jason.Encoder,
           only: [
             :id,
             :tenant_id,
             :conversation_id,
             :tool_name,
             :arguments,
             :result,
             :result_type,
             :duration_ms,
             :iteration,
             :inserted_at
           ]}
  schema "tool_traces" do
    field(:tenant_id, :binary_id)
    field(:conversation_id, :binary_id)
    field(:tool_name, :string)
    field(:arguments, :map, default: %{})
    field(:result, :map, default: %{})
    field(:result_type, :string, default: "ok")
    field(:duration_ms, :integer)
    field(:iteration, :integer, default: 0)

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @required_fields ~w(tenant_id conversation_id tool_name result_type iteration)a
  @optional_fields ~w(arguments result duration_ms)a

  @doc "Changeset for creating a new tool trace record."
  @spec changeset(%__MODULE__{} | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(trace \\ %__MODULE__{}, attrs) do
    trace
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:result_type, @result_types)
  end
end
