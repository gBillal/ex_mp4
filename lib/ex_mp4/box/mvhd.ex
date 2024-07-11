defmodule ExMP4.Box.Mvhd do
  @moduledoc false

  import ExMP4.Box.Utils

  @type t :: %__MODULE__{}

  defstruct version: 0,
            flags: 0,
            creation_time: to_date(0),
            modification_time: to_date(0),
            timescale: 1_000,
            duration: 0,
            rate: 0x00010000,
            volume: 0x0100,
            matrix: [0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000],
            next_track_id: 0

  @spec new(Keyword.t()) :: t()
  def new(opts), do: struct!(__MODULE__, opts)

  defimpl ExMP4.Box do
    def size(%{version: 1}), do: MP4.full_box_header_size() + 108
    def size(%{version: 0}), do: MP4.full_box_header_size() + 96

    def parse(
          box,
          <<version::8, flags::24, creation_time::size(32 * (version + 1)),
            modification_time::size(32 * (version + 1)), timescale::32,
            duration::size(32 * (version + 1)), rate::32, volume::16, _reserved::80,
            matrix::binary-size(4 * 9), _pre_defined::32*6, next_track_id::32>>
        ) do
      mat = for <<value::32 <- matrix>>, do: value

      %{
        box
        | version: version,
          flags: flags,
          creation_time: to_date(creation_time),
          modification_time: to_date(modification_time),
          timescale: timescale,
          duration: duration,
          rate: rate,
          volume: volume,
          matrix: mat,
          next_track_id: next_track_id
      }
    end

    def serialize(box) do
      v = box.version + 1

      part1 =
        <<size(box)::32, "mvhd", box.version::8, box.flags::24,
          from_date(box.creation_time)::size(32 * v),
          from_date(box.modification_time)::size(32 * v), box.timescale::32,
          box.duration::size(32 * v), box.rate::32, box.volume::16, _reserved = 0::80>>

      [
        part1,
        Enum.map(box.matrix, &<<&1::32>>),
        <<_pre_defined = 0::32*6, box.next_track_id::32>>
      ]
    end
  end
end
