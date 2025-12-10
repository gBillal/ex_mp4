defmodule ExMP4.Box.Av1c do
  @moduledoc """
  A module representing an `av1C` box, which contains AV1 codec configuration.
  """

  @type t :: %__MODULE__{
          seq_profile: non_neg_integer(),
          seq_level_idx_0: non_neg_integer(),
          seq_tier_0: 0..1,
          high_bitdepth: 0..1,
          twelve_bit: 0..1,
          monochrome: 0..1,
          chroma_subsampling_x: 0..1,
          chroma_subsampling_y: 0..1,
          chroma_sample_position: non_neg_integer(),
          initial_presentation_delay_present: 0..1,
          initial_presentation_delay_minus_one: non_neg_integer(),
          config_obus: [binary()]
        }

  defstruct [
    :seq_profile,
    :seq_level_idx_0,
    :seq_tier_0,
    :high_bitdepth,
    :twelve_bit,
    :monochrome,
    :chroma_subsampling_x,
    :chroma_subsampling_y,
    :chroma_sample_position,
    :initial_presentation_delay_present,
    :initial_presentation_delay_minus_one,
    config_obus: []
  ]

  if Code.ensure_loaded?(MediaCodecs) do
    import MediaCodecs.Helper, only: [bool_to_int: 1]

    alias MediaCodecs.AV1.OBU

    @doc """
    Creates a new `av1c` box from sequence header OBU.

    Only available if [MediaCodecs](https://hex.pm/packages/media_codecs) is installed.

        iex> obu = <<10, 11, 0, 0, 0, 66, 167, 191, 230, 46, 223, 200, 66>>
        iex> ExMP4.Box.Av1c.new(obu)
        %ExMP4.Box.Av1c{
          chroma_sample_position: 0,
          chroma_subsampling_x: 1,
          chroma_subsampling_y: 1,
          config_obus: [<<10, 11, 0, 0, 0, 66, 167, 191, 230, 46, 223, 200, 66>>],
          high_bitdepth: 0,
          initial_presentation_delay_minus_one: 0,
          initial_presentation_delay_present: 0,
          monochrome: 0,
          seq_level_idx_0: 8,
          seq_profile: 0,
          seq_tier_0: 0,
          twelve_bit: 0
        }
    """
    @spec new(binary()) :: t()
    def new(obu) do
      %OBU{payload: sequence_header} = OBU.parse!(obu)
      color_config = sequence_header.color_config

      %__MODULE__{
        seq_profile: sequence_header.seq_profile,
        seq_level_idx_0: sequence_header.operating_points[0].seq_level_idx,
        seq_tier_0: sequence_header.operating_points[0].seq_tier,
        high_bitdepth: bool_to_int(color_config[:high_bitdepth]),
        twelve_bit: bool_to_int(color_config[:high_bitdepth] == 12),
        monochrome: bool_to_int(color_config[:monochrome]),
        chroma_subsampling_x: color_config[:subsampling_x],
        chroma_subsampling_y: color_config[:subsampling_y],
        chroma_sample_position: color_config[:chroma_sample_position],
        initial_presentation_delay_present: 0,
        initial_presentation_delay_minus_one: 0,
        config_obus: [obu]
      }
    end
  end

  defimpl ExMP4.Box do
    def size(box) do
      ExMP4.header_size() + IO.iodata_length(box.config_obus) + 4
    end

    def parse(
          box,
          <<1::1, 1::7, seq_profile::3, seq_level_idx_0::5, seq_tier_0::1, high_bitdepth::1,
            twelve_bit::1, monochrome::1, chroma_subsampling_x::1, chroma_subsampling_y::1,
            chroma_sample_position::2, _reserved::3, initial_presentation_delay_present::1,
            initial_presentation_delay_minus_one::4, config_obus::binary>>
        ) do
      # Parse config_obus
      %{
        box
        | seq_profile: seq_profile,
          seq_level_idx_0: seq_level_idx_0,
          seq_tier_0: seq_tier_0,
          high_bitdepth: high_bitdepth,
          twelve_bit: twelve_bit,
          monochrome: monochrome,
          chroma_subsampling_x: chroma_subsampling_x,
          chroma_subsampling_y: chroma_subsampling_y,
          chroma_sample_position: chroma_sample_position,
          initial_presentation_delay_present: initial_presentation_delay_present,
          initial_presentation_delay_minus_one: initial_presentation_delay_minus_one,
          config_obus: if(config_obus == <<>>, do: [], else: [config_obus])
      }
    end

    def serialize(box) do
      [
        <<size(box)::32>>,
        "av1C",
        <<0x81>>,
        <<box.seq_profile::3, box.seq_level_idx_0::5, box.seq_tier_0::1, box.high_bitdepth::1,
          box.twelve_bit::1, box.monochrome::1, box.chroma_subsampling_x::1,
          box.chroma_subsampling_y::1, box.chroma_sample_position::2, 0::3,
          box.initial_presentation_delay_present::1,
          box.initial_presentation_delay_minus_one::4>>,
        box.config_obus
      ]
    end
  end
end
