defmodule ExMP4.Box.Stsd do
  @moduledoc """
  A module representing an `stsd` box.

  The sample description table gives detailed information about the coding type used, and any initialization
  information needed for that coding.
  """

  import ExMP4.Box.Utils, only: [parse_header: 1]

  alias ExMP4.Box.{Avc, Mp4a}

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          avc1: Avc.t() | nil,
          avc3: Avc.t() | nil,
          mp4a: Mp4a.t() | nil
        }

  defstruct version: 0, flags: 0, avc1: nil, avc3: nil, mp4a: nil

  defimpl ExMP4.Box do
    def size(box) do
      avc_size = if box.avc1 || box.avc3, do: ExMP4.Box.size(box.avc1 || box.avc3), else: 0
      mp4a_size = if box.mp4a, do: ExMP4.Box.size(box.mp4a), else: 0
      MP4.full_box_header_size() + 4 + avc_size + mp4a_size
    end

    def parse(box, <<version::8, flags::24, 1::32, rest::binary>>) do
      %{box | version: version, flags: flags}
      |> do_parse(rest)
    end

    def serialize(box) do
      avc_data = if box.avc1 || box.avc3, do: ExMP4.Box.serialize(box.avc1 || box.avc3), else: []
      mp4a_data = if box.mp4a, do: ExMP4.Box.serialize(box.mp4a), else: []

      [<<size(box)::32, "stsd", box.version::8, box.flags::24, 1::32>>, avc_data, mp4a_data]
    end

    defp do_parse(box, <<>>), do: box

    defp do_parse(box, data) do
      {box, rest} =
        case parse_header(data) do
          {"avc1", box_data, rest} ->
            box = %{box | avc1: ExMP4.Box.parse(%Avc{}, box_data)}
            {box, rest}

          {"avc3", box_data, rest} ->
            box = %{box | avc1: ExMP4.Box.parse(%Avc{}, box_data)}
            {box, rest}

          {"mp4a", box_data, rest} ->
            box = %{box | mp4a: ExMP4.Box.parse(%Mp4a{}, box_data)}
            {box, rest}

          {_box_name, _box_data, rest} ->
            {box, rest}
        end

      do_parse(box, rest)
    end
  end
end
