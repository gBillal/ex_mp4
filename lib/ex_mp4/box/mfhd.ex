defmodule ExMP4.Box.Mfhd do
  @moduledoc """
  A module repsenting an `mfhd` box.

  The movie fragment header contains a sequence number, as a safety check.
  """

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          sequence_number: non_neg_integer()
        }

  defstruct version: 0, flags: 0, sequence_number: 0

  defimpl ExMP4.Box do
    def size(_box), do: ExMP4.full_box_header_size() + 4

    def parse(box, <<version::8, flags::24, sequence_number::32>>) do
      %{
        box
        | version: version,
          flags: flags,
          sequence_number: sequence_number
      }
    end

    def serialize(box) do
      <<size(box)::32, "mfhd", box.version::8, box.flags::24, box.sequence_number::32>>
    end
  end
end
