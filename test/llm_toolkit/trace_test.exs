defmodule LlmToolkit.TraceTest do
  use ExUnit.Case, async: true

  alias LlmToolkit.Trace

  @valid_attrs %{
    tenant_id: "550e8400-e29b-41d4-a716-446655440000",
    conversation_id: "550e8400-e29b-41d4-a716-446655440001",
    tool_name: "echo",
    arguments: %{"message" => "hello"},
    result: %{"output" => "hello"},
    result_type: "ok",
    duration_ms: 42,
    iteration: 0
  }

  describe "changeset/2" do
    test "valid attrs produce a valid changeset" do
      changeset = Trace.changeset(%Trace{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires tenant_id, conversation_id, tool_name" do
      changeset = Trace.changeset(%Trace{}, %{})
      refute changeset.valid?

      errors = changeset_errors(changeset)
      assert errors[:tenant_id]
      assert errors[:conversation_id]
      assert errors[:tool_name]
    end

    test "validates result_type inclusion" do
      changeset = Trace.changeset(%Trace{}, %{@valid_attrs | result_type: "invalid"})
      refute changeset.valid?

      errors = changeset_errors(changeset)
      assert errors[:result_type]
    end

    test "accepts valid result_type values" do
      for type <- ~w(ok error) do
        changeset = Trace.changeset(%Trace{}, %{@valid_attrs | result_type: type})
        assert changeset.valid?, "expected #{type} to be valid"
      end
    end

    test "large args/result payloads are accepted" do
      large_map = for i <- 1..100, into: %{}, do: {"key_#{i}", String.duplicate("x", 100)}

      changeset =
        Trace.changeset(%Trace{}, %{
          @valid_attrs
          | arguments: large_map,
            result: large_map
        })

      assert changeset.valid?
    end

    test "optional fields can be omitted" do
      attrs = Map.drop(@valid_attrs, [:arguments, :result, :duration_ms])
      changeset = Trace.changeset(%Trace{}, attrs)
      assert changeset.valid?
    end

    test "defaults are applied" do
      changeset =
        Trace.changeset(%Trace{}, %{
          tenant_id: @valid_attrs.tenant_id,
          conversation_id: @valid_attrs.conversation_id,
          tool_name: @valid_attrs.tool_name,
          result_type: @valid_attrs.result_type,
          iteration: @valid_attrs.iteration
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :arguments) == %{}
      assert Ecto.Changeset.get_field(changeset, :result) == %{}
    end
  end

  describe "schema metadata" do
    test "has correct primary key" do
      assert Trace.__schema__(:primary_key) == [:id]
      assert Trace.__schema__(:type, :id) == :binary_id
    end

    test "has the expected fields" do
      fields = Trace.__schema__(:fields)
      assert :id in fields
      assert :tenant_id in fields
      assert :conversation_id in fields
      assert :tool_name in fields
      assert :arguments in fields
      assert :result in fields
      assert :result_type in fields
      assert :duration_ms in fields
      assert :iteration in fields
      assert :inserted_at in fields
    end

    test "updated_at is disabled" do
      refute :updated_at in Trace.__schema__(:fields)
    end
  end

  describe "Jason.Encoder derive" do
    test "trace struct can be encoded" do
      trace = %Trace{
        id: "550e8400-e29b-41d4-a716-446655440000",
        tenant_id: "550e8400-e29b-41d4-a716-446655440001",
        conversation_id: "550e8400-e29b-41d4-a716-446655440002",
        tool_name: "echo",
        arguments: %{"x" => 1},
        result: %{"y" => 2},
        result_type: "ok",
        duration_ms: 10,
        iteration: 0,
        inserted_at: ~U[2024-01-01 00:00:00Z]
      }

      json = Jason.encode!(trace)
      decoded = Jason.decode!(json)

      assert decoded["id"] == trace.id
      assert decoded["tool_name"] == "echo"
      assert decoded["arguments"] == %{"x" => 1}
      assert decoded["result_type"] == "ok"
      refute Map.has_key?(decoded, "__struct__")
    end
  end

  # --- Helpers ----------------------------------------------------------------

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
