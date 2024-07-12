defmodule ExMP4.Box.Tfdt do
  @moduledoc """
  A module repsenting an `tfdt` box.

  The Track Fragment Base Media Decode Time Box provides the absolute decode time,
  measured on the media timeline, of the first sample in decode order in the track fragment.
  """

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          base_media_decode_time: integer()
        }

  defstruct version: 0, flags: 0, base_media_decode_time: 0

  defimpl ExMP4.Box do
    def size(%{version: 0}), do: ExMP4.full_box_header_size() + 4
    def size(%{version: 1}), do: ExMP4.full_box_header_size() + 8

    def parse(box, <<version::8, flags::24, base_media_decode_time::size(32 * (version + 1))>>) do
      %{box | version: version, flags: flags, base_media_decode_time: base_media_decode_time}
    end

    def serialize(box) do
      <<size(box)::32, "tfdt", box.version::8, box.flags::24,
        box.base_media_decode_time::size(32 * (box.version + 1))>>
    end
  end
end
