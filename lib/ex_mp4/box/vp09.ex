defmodule ExMP4.Box.VP09 do
  @moduledoc """
  A module representing an `vp09` box.
  """

  import ExMP4.Box.Utils, only: [parse_header: 1]

  alias ExMP4.Box.{Pasp, Vpcc}

  @type t :: %__MODULE__{
          data_reference_index: integer(),
          width: integer(),
          height: integer(),
          horizresolution: integer(),
          vertresolution: integer(),
          frame_count: integer(),
          compressor_name: binary(),
          depth: integer(),
          vpcC: Vpcc.t(),
          pasp: Pasp.t() | nil
        }

  defstruct data_reference_index: 1,
            width: 0,
            height: 0,
            horizresolution: 0x00480000,
            vertresolution: 0x00480000,
            frame_count: 1,
            compressor_name: <<10, "VPC Coding", 0::21*8>>,
            depth: 0x0018,
            vpcC: nil,
            pasp: nil

  defimpl ExMP4.Box do
    def size(box) do
      ExMP4.header_size() + 70 + ExMP4.Box.size(box.vpcC) + ExMP4.Box.size(box.pasp) + 8
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
        <<size(box)::32, "vp09"::binary, 0::48, box.data_reference_index::16, 0::128,
          box.width::16, box.height::16, box.horizresolution::32, box.vertresolution::32, 0::32,
          box.frame_count::16, box.compressor_name::binary, box.depth::16, -1::16-signed>>

      [data, ExMP4.Box.serialize(box.vpcC)]
    end

    defp do_parse(box, <<>>), do: box

    defp do_parse(box, data) do
      {box, rest} =
        case parse_header(data) do
          {"vpcC", box_data, rest} ->
            box = %{box | vpcC: ExMP4.Box.parse(%Vpcc{}, box_data)}
            {box, rest}

          {"pasp", box_data, rest} ->
            box = %{box | pasp: ExMP4.Box.parse(%Pasp{}, box_data)}
            {box, rest}

          {_box_name, _box_data, rest} ->
            {box, rest}
        end

      do_parse(box, rest)
    end
  end
end
