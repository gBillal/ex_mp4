defmodule ExMP4.Box.Minf do
  @moduledoc """
  A module representing a `minf` box.

  This box contains all the objects that declare characteristic information of the media in the track.
  """

  import ExMP4.Box.Utils, only: [parse_header: 1]

  alias ExMP4.Box.{Dinf, Smhd, Stbl, Vmhd}

  @type t :: %__MODULE__{
          vmhd: Vmhd.t() | nil,
          smhd: Smhd.t() | nil,
          dinf: Dinf.t(),
          stbl: Stbl.t()
        }

  defstruct vmhd: nil, smhd: nil, dinf: %Dinf{}, stbl: %Stbl{}

  defimpl ExMP4.Box do
    def size(box) do
      vmhd_size = if box.vmhd, do: ExMP4.Box.size(box.vmhd), else: 0
      smhd_size = if box.smhd, do: ExMP4.Box.size(box.smhd), else: 0

      ExMP4.header_size() + vmhd_size + smhd_size + ExMP4.Box.size(box.dinf) +
        ExMP4.Box.size(box.stbl)
    end

    def parse(box, data), do: do_parse(box, data)

    def serialize(box) do
      vmhd_data = if box.vmhd, do: ExMP4.Box.serialize(box.vmhd), else: <<>>
      smhd_data = if box.smhd, do: ExMP4.Box.serialize(box.smhd), else: <<>>

      [
        <<size(box)::32, "minf">>,
        vmhd_data,
        smhd_data,
        ExMP4.Box.serialize(box.dinf),
        ExMP4.Box.serialize(box.stbl)
      ]
    end

    defp do_parse(box, <<>>), do: box

    defp do_parse(box, data) do
      {box, rest} =
        case parse_header(data) do
          {"vmhd", box_data, rest} ->
            box = %{box | vmhd: ExMP4.Box.parse(%Vmhd{}, box_data)}
            {box, rest}

          {"smhd", box_data, rest} ->
            box = %{box | smhd: ExMP4.Box.parse(%Smhd{}, box_data)}
            {box, rest}

          {"dinf", box_data, rest} ->
            box = %{box | dinf: ExMP4.Box.parse(%Dinf{}, box_data)}
            {box, rest}

          {"stbl", box_data, rest} ->
            box = %{box | stbl: ExMP4.Box.parse(%Stbl{}, box_data)}
            {box, rest}

          {_box_name, _box_data, rest} ->
            # box = %{box | mdia: ExMP4.Box.parse(%Mdia{}, box_data)}
            {box, rest}
        end

      do_parse(box, rest)
    end
  end
end
