defmodule ExMP4.Box.Moof do
  @moduledoc """
  A module representing an `moof` box.

  The movie fragments extend the presentation in time. They provide the information that
  would previously have been in the Movie Box.
  """

  import ExMP4.Box.Utils, only: [parse_header: 1]

  alias ExMP4.Box.{Mfhd, Traf}

  @type t :: %__MODULE__{
          mfhd: Mfhd.t(),
          traf: [Traf.t()]
        }

  defstruct mfhd: %Mfhd{}, traf: []

  @doc """
  Update the data base offset.

  if `base_is_moof` is `false`, the `base_data_offset` is set in the `tfhd` box and
  `trun` boxes updated to include the `data_offset` starting from 0 for the first `trun`.

  If `base_is_moof` is `true`, the `base_data_offset` of `tfhd` is set to `0` and the first
  `trun` will have `base_data_offset` as the starting offset.
  """
  @spec update_base_offsets(t(), integer(), boolean()) :: t()
  def update_base_offsets(%{traf: trafs} = moof, base_data_offset, base_is_moof) do
    {trafs, _offset} =
      Enum.map_reduce(trafs, base_data_offset, fn traf, base_offset ->
        new_offset = base_offset + Traf.total_size(traf)

        if base_is_moof,
          do: {Traf.update_base_offset(traf, 0, base_offset), new_offset},
          else: {Traf.update_base_offset(traf, base_offset), new_offset}
      end)

    %{moof | traf: trafs}
  end

  defimpl ExMP4.Box do
    def size(box) do
      ExMP4.header_size() + ExMP4.Box.size(box.mfhd) + ExMP4.Box.size(box.traf)
    end

    def parse(box, data), do: do_parse(box, data)

    def serialize(box) do
      [
        <<size(box)::32, "moof">>,
        ExMP4.Box.serialize(box.mfhd),
        ExMP4.Box.serialize(box.traf)
      ]
    end

    defp do_parse(box, <<>>), do: box

    defp do_parse(box, data) do
      {box, rest} =
        case parse_header(data) do
          {"mfhd", box_data, rest} ->
            box = %{box | mfhd: ExMP4.Box.parse(%Mfhd{}, box_data)}
            {box, rest}

          {"traf", box_data, rest} ->
            box = %{box | traf: box.traf ++ [ExMP4.Box.parse(%Traf{}, box_data)]}
            {box, rest}

          {_other, _box_data, rest} ->
            {box, rest}
        end

      do_parse(box, rest)
    end
  end
end
