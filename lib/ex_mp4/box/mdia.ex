defmodule ExMP4.Box.Mdia do
  @moduledoc """
  A module representing a media container box.
  """

  import ExMP4.Box.Utils, only: [parse_header: 1]

  alias ExMP4.Box.{Hdlr, Mdhd, Minf}

  @type t :: %__MODULE__{
          mdhd: Mdhd.t(),
          hdlr: Hdlr.t(),
          minf: Minf.t()
        }

  defstruct mdhd: %Mdhd{}, hdlr: %Hdlr{}, minf: %Minf{}

  defimpl ExMP4.Box do
    def size(box) do
      ExMP4.header_size() + ExMP4.Box.size(box.mdhd) + ExMP4.Box.size(box.hdlr) + ExMP4.Box.size(box.minf)
    end

    def parse(box, data), do: do_parse(box, data)

    def serialize(box) do
      [
        <<size(box)::32, "mdia">>,
        ExMP4.Box.serialize(box.mdhd),
        ExMP4.Box.serialize(box.hdlr),
        ExMP4.Box.serialize(box.minf)
      ]
    end

    defp do_parse(box, <<>>), do: box

    defp do_parse(box, data) do
      {box, rest} =
        case parse_header(data) do
          {"mdhd", box_data, rest} ->
            box = %{box | mdhd: ExMP4.Box.parse(%Mdhd{}, box_data)}
            {box, rest}

          {"hdlr", box_data, rest} ->
            box = %{box | hdlr: ExMP4.Box.parse(%Hdlr{}, box_data)}
            {box, rest}

          {"minf", box_data, rest} ->
            box = %{box | minf: ExMP4.Box.parse(%Minf{}, box_data)}
            {box, rest}

          {_box_name, _box_data, rest} ->
            # box = %{box | mdia: ExMP4.Box.parse(%Mdia{}, box_data)}
            {box, rest}
        end

      do_parse(box, rest)
    end
  end
end
