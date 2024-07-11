defmodule ExMP4.Box.Moov do
  @moduledoc """
  A module representing a `moov` box.
  """

  import ExMP4.Box.Utils, only: [parse_header: 1]

  alias ExMP4.Box.{Mvhd, Trak}

  @type t :: %__MODULE__{
          mvhd: Mvhd.t(),
          traks: [Trak.t()]
        }

  defstruct mvhd: %Mvhd{}, traks: []

  defimpl ExMP4.Box do
    def size(box) do
      trak_size = Enum.map(box.traks, &ExMP4.Box.size/1) |> Enum.sum()
      ExMP4.header_size() + ExMP4.Box.size(box.mvhd) + trak_size
    end

    def parse(box, data), do: do_parse(box, data)

    def serialize(box) do
      [
        <<size(box)::32, "moov">>,
        ExMP4.Box.serialize(box.mvhd),
        Enum.map(box.traks, &ExMP4.Box.serialize/1)
      ]
    end

    defp do_parse(box, <<>>), do: box

    defp do_parse(box, data) do
      {box, rest} =
        case parse_header(data) do
          {"mvhd", box_data, rest} ->
            box = %{box | mvhd: ExMP4.Box.parse(%Mvhd{}, box_data)}
            {box, rest}

          {"trak", box_data, rest} ->
            box = %{box | traks: box.traks ++ [ExMP4.Box.parse(%Trak{}, box_data)]}
            {box, rest}

          {_box_name, _box_data, rest} ->
            # box = %{box | mdia: ExMP4.Box.parse(%Mdia{}, box_data)}
            {box, rest}
        end

      do_parse(box, rest)
    end
  end
end
