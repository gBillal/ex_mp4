defmodule ExMP4.Box.Pasp do
  @moduledoc """
  A module representing an `pasp` box.
  """

  @type t :: %__MODULE__{
          h_spacing: integer(),
          v_spacing: integer()
        }

  defstruct h_spacing: 1, v_spacing: 1

  defimpl ExMP4.Box do
    def size(_box), do: ExMP4.header_size() + 8

    def parse(box, <<h_spacing::32, v_spacing::32>>) do
      %{box | h_spacing: h_spacing, v_spacing: v_spacing}
    end

    def serialize(box) do
      <<size(box)::32, "pasp", box.h_spacing::32, box.v_spacing::32>>
    end
  end
end
