defmodule ExMP4.Box.Fpcm do
  @moduledoc """
  A module representing an `fpcm` box.
  """

  import ExMP4.Box.Utils, only: [parse_header: 1]

  @type t :: %__MODULE__{
          data_reference_index: integer(),
          channel_count: integer(),
          sample_size: integer(),
          sample_rate: {integer(), integer()},
          pcmC: ExMP4.Box.Pcmc.t()
        }

  defstruct [:channel_count, :sample_size, :sample_rate, :pcmC, data_reference_index: 1]

  defimpl ExMP4.Box do
    alias ExMP4.Box.Pcmc

    def size(box), do: ExMP4.header_size() + 28 + ExMP4.Box.size(box.pcmC)

    def parse(
          box,
          <<0::48, data_reference_index::16, 0::64, channel_count::16, sample_size::16, 0::32,
            sample_rate_hi::16, sample_rate_lo::16, rest::binary>>
        ) do
      %{
        box
        | data_reference_index: data_reference_index,
          channel_count: channel_count,
          sample_size: sample_size,
          sample_rate: {sample_rate_hi, sample_rate_lo}
      }
      |> do_parse(rest)
    end

    def serialize(box) do
      {rate_hi, rate_lo} = box.sample_rate

      data =
        <<size(box)::32, "fpcm"::binary, 0::48, box.data_reference_index::16, 0::64,
          box.channel_count::16, box.sample_size::16, 0::32, rate_hi::16, rate_lo::16>>

      [data, ExMP4.Box.serialize(box.pcmC)]
    end

    defp do_parse(box, <<>>), do: box

    defp do_parse(box, data) do
      {box, rest} =
        case parse_header(data) do
          {"pcmC", box_data, rest} ->
            box = %{box | pcmC: ExMP4.Box.parse(%Pcmc{}, box_data)}
            {box, rest}

          {_box_name, _box_data, rest} ->
            {box, rest}
        end

      do_parse(box, rest)
    end
  end
end
