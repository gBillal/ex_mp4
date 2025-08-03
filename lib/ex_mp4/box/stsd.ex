defmodule ExMP4.Box.Stsd do
  @moduledoc """
  A module representing an `stsd` box.

  The sample description table gives detailed information about the coding type used, and any initialization
  information needed for that coding.
  """

  import ExMP4.Box.Utils, only: [parse_header: 1]

  alias ExMP4.Box
  alias ExMP4.Box.{Av01, Avc, Fpcm, Hevc, Ipcm, Mp4a, Opus, VP08, VP09}

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          av01: Av01.t() | nil,
          avc1: Avc.t() | nil,
          avc3: Avc.t() | nil,
          mp4a: Mp4a.t() | nil,
          hvc1: Hevc.t() | nil,
          hev1: Hevc.t() | nil,
          vp08: VP08.t() | nil,
          vp09: VP09.t() | nil,
          ipcm: Ipcm.t() | nil,
          fpcm: Fpcm.t() | nil,
          opus: Opus.t() | nil
        }

  defstruct version: 0,
            flags: 0,
            av01: nil,
            avc1: nil,
            avc3: nil,
            mp4a: nil,
            hvc1: nil,
            hev1: nil,
            vp08: nil,
            vp09: nil,
            ipcm: nil,
            fpcm: nil,
            opus: nil

  defimpl ExMP4.Box do
    @codecs %{
      "av01" => %Av01{},
      "avc1" => %Avc{},
      "avc3" => %Avc{},
      "mp4a" => %Mp4a{},
      "hvc1" => %Hevc{},
      "hev1" => %Hevc{},
      "vp08" => %VP08{},
      "vp09" => %VP09{},
      "ipcm" => %Ipcm{},
      "fpcm" => %Fpcm{},
      "Opus" => %Opus{}
    }

    def size(box) do
      ExMP4.full_box_header_size() + 4 + Box.size(box.av01) + Box.size(box.avc1) +
        Box.size(box.avc3) + Box.size(box.mp4a) + Box.size(box.hvc1) + Box.size(box.hev1) +
        Box.size(box.vp08) + Box.size(box.vp09) + Box.size(box.ipcm) + Box.size(box.fpcm) +
        Box.size(box.opus)
    end

    def parse(box, <<version::8, flags::24, 1::32, rest::binary>>) do
      %{box | version: version, flags: flags}
      |> do_parse(rest)
    end

    def serialize(box) do
      [
        <<size(box)::32, "stsd", box.version::8, box.flags::24, 1::32>>,
        Box.serialize(box.av01),
        Box.serialize(box.avc1),
        Box.serialize(box.avc3),
        Box.serialize(box.mp4a),
        Box.serialize(box.hvc1),
        Box.serialize(box.hev1),
        Box.serialize(box.vp08),
        Box.serialize(box.vp09),
        Box.serialize(box.ipcm),
        Box.serialize(box.fpcm),
        Box.serialize(box.opus)
      ]
    end

    defp do_parse(box, <<>>), do: box

    defp do_parse(box, data) do
      {box_name, box_data, rest} = parse_header(data)

      box =
        case Map.fetch(@codecs, box_name) do
          {:ok, codec_struct} ->
            box_name = String.downcase(box_name)
            Map.put(box, String.to_atom(box_name), Box.parse(codec_struct, box_data))

          :error ->
            box
        end

      do_parse(box, rest)
    end
  end
end
