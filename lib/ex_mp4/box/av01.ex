defmodule ExMP4.Box.Av01 do
  @moduledoc """
  A module representing an `av01` box, which contains AV1 codec configuration.
  """

  import ExMP4.Box.Utils, only: [parse_header: 1]

  alias ExMP4.Box
  alias ExMP4.Box.{Av1c, Pasp}

  @type t :: %__MODULE__{
          data_reference_index: non_neg_integer(),
          width: non_neg_integer(),
          height: non_neg_integer(),
          horizresolution: non_neg_integer(),
          vertresolution: non_neg_integer(),
          frame_count: non_neg_integer(),
          compressor_name: binary(),
          depth: non_neg_integer(),
          av1c: Av1c.t(),
          pasp: nil | Pasp.t()
        }

  defstruct data_reference_index: 1,
            width: 0,
            height: 0,
            horizresolution: 0x00480000,
            vertresolution: 0x00480000,
            frame_count: 1,
            compressor_name: <<10, "AOM Coding", 0::8*21>>,
            depth: 0x0018,
            av1c: %Av1c{},
            pasp: nil

  defimpl Box do
    def size(box) do
      ExMP4.header_size() + 78 + Box.size(box.av1c) + Box.size(box.pasp)
    end

    def parse(
          box,
          <<0::48, data_reference_index::16, 0::128, width::16, height::16, horizresolution::32,
            vertresolution::32, 0::32, frame_count::16, compressor_name::binary-size(32),
            depth::16, -1::16-signed, rest::binary>>
        ) do
      %{
        box
        | data_reference_index: data_reference_index,
          width: width,
          height: height,
          horizresolution: horizresolution,
          vertresolution: vertresolution,
          frame_count: frame_count,
          compressor_name: compressor_name,
          depth: depth
      }
      |> do_parse(rest)
    end

    def serialize(box) do
      data =
        <<size(box)::32, "av01"::binary, 0::48, box.data_reference_index::16, 0::128,
          box.width::16, box.height::16, box.horizresolution::32, box.vertresolution::32, 0::32,
          box.frame_count::16, box.compressor_name::binary, box.depth::16, -1::16-signed>>

      [data, Box.serialize(box.av1c), Box.serialize(box.pasp)]
    end

    defp do_parse(box, <<>>), do: box

    defp do_parse(box, data) do
      {box, rest} =
        case parse_header(data) do
          {"av1C", box_data, rest} ->
            box = %{box | av1c: Box.parse(%Av1c{}, box_data)}
            {box, rest}

          {"pasp", box_data, rest} ->
            box = %{box | pasp: Box.parse(%Pasp{}, box_data)}
            {box, rest}

          {_box_name, _box_data, rest} ->
            {box, rest}
        end

      do_parse(box, rest)
    end
  end
end
