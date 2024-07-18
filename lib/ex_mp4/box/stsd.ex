defmodule ExMP4.Box.Stsd do
  @moduledoc """
  A module representing an `stsd` box.

  The sample description table gives detailed information about the coding type used, and any initialization
  information needed for that coding.
  """

  import ExMP4.Box.Utils, only: [parse_header: 1]

  alias ExMP4.Box
  alias ExMP4.Box.{Avc, Hevc, Mp4a}

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          avc1: Avc.t() | nil,
          avc3: Avc.t() | nil,
          mp4a: Mp4a.t() | nil,
          hvc1: Hevc.t() | nil,
          hev1: Hevc.t() | nil
        }

  defstruct version: 0, flags: 0, avc1: nil, avc3: nil, mp4a: nil, hvc1: nil, hev1: nil

  defimpl ExMP4.Box do
    def size(box) do
      ExMP4.full_box_header_size() + 4 + Box.size(box.avc1) + Box.size(box.avc3) +
        Box.size(box.mp4a) + +Box.size(box.hvc1) + +Box.size(box.hev1)
    end

    def parse(box, <<version::8, flags::24, 1::32, rest::binary>>) do
      %{box | version: version, flags: flags}
      |> do_parse(rest)
    end

    def serialize(box) do
      [
        <<size(box)::32, "stsd", box.version::8, box.flags::24, 1::32>>,
        Box.serialize(box.avc1),
        Box.serialize(box.avc3),
        Box.serialize(box.mp4a),
        Box.serialize(box.hvc1),
        Box.serialize(box.hev1)
      ]
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

          {"hvc1", box_data, rest} ->
            box = %{box | hvc1: ExMP4.Box.parse(%Hevc{}, box_data)}
            {box, rest}

          {"hev1", box_data, rest} ->
            box = %{box | hev1: ExMP4.Box.parse(%Hevc{}, box_data)}
            {box, rest}

          {_box_name, _box_data, rest} ->
            {box, rest}
        end

      do_parse(box, rest)
    end
  end
end
