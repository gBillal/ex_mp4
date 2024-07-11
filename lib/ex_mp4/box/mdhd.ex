defmodule ExMP4.Box.Mdhd do
  @moduledoc """
  A module representing a `mdhd` box.

  The media header declares overall information that is media‐independent, and relevant to
  characteristics of the media in a track.
  """

  import ExMP4.Box.Utils

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          creation_time: DateTime.t(),
          modification_time: DateTime.t(),
          timescale: integer(),
          duration: integer(),
          language: String.t()
        }

  defstruct version: 0,
            flags: 0,
            creation_time: to_date(0),
            modification_time: to_date(0),
            timescale: 0,
            duration: 0,
            language: "und"

  defimpl ExMP4.Box do
    def size(%{version: 0}), do: MP4.full_box_header_size() + 20
    def size(%{version: 1}), do: MP4.full_box_header_size() + 32

    def parse(
          box,
          <<version::8, flags::24, creation_time::size(32 * (version + 1)),
            modification_time::size(32 * (version + 1)), timescale::32,
            duration::size(32 * (version + 1)), 0::1, language::15, 0::16>>
        ) do
      language =
        [
          (Bitwise.bsr(language, 10) |> Bitwise.band(0x1F)) + 0x60,
          (Bitwise.bsr(language, 5) |> Bitwise.band(0x1F)) + 0x60,
          Bitwise.band(language, 0x1F) + 0x60
        ]
        |> :binary.list_to_bin()

      %{
        box
        | version: version,
          flags: flags,
          creation_time: to_date(creation_time),
          modification_time: to_date(modification_time),
          timescale: timescale,
          duration: duration,
          language: language
      }
    end

    def serialize(box) do
      v = box.version + 1

      language =
        box.language
        |> :binary.bin_to_list()
        |> Enum.reduce(<<>>, &<<&2::bitstring, &1 - 0x60::5>>)

      <<size(box)::32, "mdhd", box.version::8, box.flags::24,
        from_date(box.creation_time)::size(32 * v),
        from_date(box.modification_time)::size(32 * v), box.timescale::32,
        box.duration::size(32 * v), _pad = 0::1, language::bitstring, _pre_defined = 0::16>>
    end
  end
end
