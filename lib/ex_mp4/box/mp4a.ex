defmodule ExMP4.Box.Mp4a do
  @moduledoc """
  A module representing an `mp4a` boxe.
  """

  import ExMP4.Box.Utils, only: [parse_header: 1]

  @type t :: %__MODULE__{
          data_reference_index: integer(),
          channel_count: integer(),
          sample_size: integer(),
          sample_rate: {integer(), integer()},
          esds: binary()
        }

  defstruct data_reference_index: 0,
            channel_count: 2,
            sample_size: 16,
            sample_rate: {0, 0},
            esds: <<>>

  defimpl ExMP4.Box do
    def size(box), do: ExMP4.header_size() + 28 + byte_size(box.esds) + 8

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
      esds = <<byte_size(box.esds) + 8::32, "esds", box.esds::binary>>

      data =
        <<size(box)::32, "mp4a"::binary, 0::48, box.data_reference_index::16, 0::64,
          box.channel_count::16, box.sample_size::16, 0::32, rate_hi::16, rate_lo::16>>

      [data, esds]
    end

    defp do_parse(box, <<>>), do: box

    defp do_parse(box, data) do
      {box, rest} =
        case parse_header(data) do
          {"esds", box_data, rest} ->
            box = %{box | esds: box_data}
            {box, rest}

          {_box_name, _box_data, rest} ->
            {box, rest}
        end

      do_parse(box, rest)
    end
  end
end
