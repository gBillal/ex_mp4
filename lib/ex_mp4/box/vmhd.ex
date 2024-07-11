defmodule ExMP4.Box.Vmhd do
  @moduledoc """
  A module representing a `vmhd` box.

  The video media header contains general presentation information, independent of the coding, for video media.
  """

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          graphics_mod: integer(),
          opcolor: [integer()]
        }

  defstruct version: 0, flags: 1, graphics_mod: 0, opcolor: [0, 0, 0]

  defimpl ExMP4.Box do
    def size(_box), do: MP4.full_box_header_size() + 8

    def parse(
          box,
          <<version::8, flags::24, graphics_mod::16, opcolor1::16, opcolor2::16, opcolor3::16>>
        ) do
      %{
        box
        | version: version,
          flags: flags,
          graphics_mod: graphics_mod,
          opcolor: [opcolor1, opcolor2, opcolor3]
      }
    end

    def serialize(box) do
      opcolor = Enum.map_join(box.opcolor, &<<&1::16>>)

      <<size(box)::32, "vmhd", box.version::8, box.flags::24, box.graphics_mod::16,
        opcolor::binary>>
    end
  end
end
