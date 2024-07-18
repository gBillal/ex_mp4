defmodule ExMP4.Box.Tkhd do
  @moduledoc """
  A module representing the track header box.
  """

  import ExMP4.Box.Utils

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          creation_time: DateTime.t(),
          modification_time: DateTime.t(),
          track_id: integer(),
          duration: integer(),
          layer: integer(),
          alternate_group: integer(),
          volume: integer(),
          matrix: [integer()],
          width: {integer(), integer()},
          height: {integer(), integer()}
        }

  defstruct version: 0,
            flags: 7,
            creation_time: to_date(0),
            modification_time: to_date(0),
            track_id: 0,
            duration: 0,
            layer: 0,
            alternate_group: 0,
            volume: 0,
            matrix: [0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000],
            width: {0, 0},
            height: {0, 0}

  defimpl ExMP4.Box do
    def size(%{version: 0}), do: ExMP4.full_box_header_size() + 80
    def size(%{version: 1}), do: ExMP4.full_box_header_size() + 96

    def parse(
          box,
          <<version::8, flags::24, creation_time::size(32 * (version + 1)),
            modification_time::size(32 * (version + 1)), track_id::32, _reserved::32,
            duration::size(32 * (version + 1)), _reserved2::64, layer::16, alternate_group::16,
            volume::16, _reserved3::16, matrix::binary-size(36), width::32, height::32>>
        ) do
      matrix = for <<value::32 <- matrix>>, do: value

      width = {Bitwise.bsr(width, 16), Bitwise.band(width, 0xFFFF)}
      height = {Bitwise.bsr(height, 16), Bitwise.band(height, 0xFFFF)}

      %{
        box
        | version: version,
          flags: flags,
          creation_time: to_date(creation_time),
          modification_time: to_date(modification_time),
          track_id: track_id,
          duration: duration,
          layer: layer,
          alternate_group: alternate_group,
          volume: volume,
          matrix: matrix,
          width: width,
          height: height
      }
    end

    def serialize(%{width: {w1, w2}, height: {h1, h2}} = box) do
      v = box.version + 1

      box_data =
        <<size(box)::32, "tkhd", box.version::8, box.flags::24,
          from_date(box.creation_time)::size(32 * v),
          from_date(box.modification_time)::size(32 * v), box.track_id::32, 0::32,
          box.duration::size(32 * v), 0::64, box.layer::16, box.alternate_group::16,
          box.volume::16, 0::16>>

      [box_data, Enum.map(box.matrix, &<<&1::32>>), <<w1::16, w2::16, h1::16, h2::16>>]
    end
  end
end
