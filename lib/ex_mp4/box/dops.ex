defmodule ExMP4.Box.Dops do
  @moduledoc """
  A module representing a `dOps` box.
  """

  @type t :: %__MODULE__{
          version: 0,
          output_channel_count: non_neg_integer(),
          pre_skip: non_neg_integer(),
          input_sample_rate: non_neg_integer(),
          output_gain: integer(),
          channel_mapping_family: non_neg_integer(),
          channel_mapping_table:
            %{
              :stream_count => non_neg_integer(),
              :coupled_count => non_neg_integer(),
              :channel_mapping => non_neg_integer()
            }
            | nil
        }

  defstruct version: 0,
            output_channel_count: 0,
            pre_skip: 0,
            input_sample_rate: 0,
            output_gain: 0,
            channel_mapping_family: 0,
            channel_mapping_table: nil

  defimpl ExMP4.Box do
    def size(%{channel_mapping_table: nil}) do
      ExMP4.header_size() + 11
    end

    def size(box) do
      ExMP4.header_size() + box.output_channel_count + 13
    end

    def parse(
          box,
          <<0, output_channel_count::8, pre_skip::16, input_sample_rate::32,
            output_gain::16-signed, channel_mapping_family::8, rest::binary>>
        ) do
      channel_mapping_table =
        if channel_mapping_family != 0 do
          <<stream_count::8, coupled_count::8,
            channel_mapping::integer-size(8 * output_channel_count)>> = rest

          %{
            stream_count: stream_count,
            coupled_count: coupled_count,
            channel_mapping: channel_mapping
          }
        end

      %{
        box
        | output_channel_count: output_channel_count,
          pre_skip: pre_skip,
          input_sample_rate: input_sample_rate,
          output_gain: output_gain,
          channel_mapping_family: channel_mapping_family,
          channel_mapping_table: channel_mapping_table
      }
    end

    def serialize(box) do
      result =
        <<size(box)::32, "dOps", 0, box.output_channel_count::8, box.pre_skip::16,
          box.input_sample_rate::32, box.output_gain::16-signed, box.channel_mapping_family::8>>

      if box.channel_mapping_table do
        <<result::binary, box.channel_mapping_table.stream_count::8,
          box.channel_mapping_table.coupled_count::8,
          box.channel_mapping_table.channel_mapping::integer-size(8 * box.output_channel_count)>>
      else
        result
      end
    end
  end
end
