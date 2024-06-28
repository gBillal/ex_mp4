defmodule ExMP4.Codec.Hevc do
  @moduledoc """
  Module responsible for parsing and generating HEVC Configuration Record.
  """

  @typedoc "Structure representing the Decoder Configuartion Record"
  @type t() :: %__MODULE__{
          vpss: [binary()],
          spss: [binary()],
          ppss: [binary()],
          profile_space: non_neg_integer(),
          tier_flag: non_neg_integer(),
          profile_idc: non_neg_integer(),
          profile_compatibility_flags: non_neg_integer(),
          constraint_indicator_flags: non_neg_integer(),
          level_idc: non_neg_integer(),
          chroma_format_idc: non_neg_integer(),
          bit_depth_luma_minus8: non_neg_integer(),
          bit_depth_chroma_minus8: non_neg_integer(),
          temporal_id_nested: non_neg_integer(),
          num_temporal_layers: non_neg_integer(),
          nalu_length_size: non_neg_integer()
        }

  @enforce_keys [
    :vpss,
    :spss,
    :ppss,
    :profile_space,
    :tier_flag,
    :profile_idc,
    :profile_compatibility_flags,
    :constraint_indicator_flags,
    :level_idc,
    :temporal_id_nested,
    :num_temporal_layers,
    :chroma_format_idc,
    :bit_depth_luma_minus8,
    :bit_depth_chroma_minus8,
    :nalu_length_size
  ]
  defstruct @enforce_keys

  @doc """
  Parses the DCR.
  """
  @spec parse(binary()) :: t()
  def parse(
        <<1::8, profile_space::2, tier_flag::1, profile_idc::5, profile_compatibility_flags::32,
          constraint_indicator_flags::48, level_idc::8, 0b1111::4,
          _min_spatial_segmentation_idc::12, 0b111111::6, _parallelism_type::2, 0b111111::6,
          chroma_format_idc::2, 0b11111::5, bit_depth_luma_minus8::3, 0b11111::5,
          bit_depth_chroma_minus8::3, _avg_frame_rate::16, _constant_frame_rate::2,
          num_temporal_layers::3, temporal_id_nested::1, length_size_minus_one::2-integer,
          num_of_arrays::8, rest::bitstring>>
      ) do
    {vpss, spss, ppss} =
      if num_of_arrays > 0 do
        {vpss, rest} = parse_pss(rest, 32)
        {spss, rest} = parse_pss(rest, 33)
        {ppss, _rest} = parse_pss(rest, 34)

        {vpss, spss, ppss}
      else
        {[], [], []}
      end

    %__MODULE__{
      vpss: vpss,
      spss: spss,
      ppss: ppss,
      profile_space: profile_space,
      tier_flag: tier_flag,
      profile_idc: profile_idc,
      profile_compatibility_flags: profile_compatibility_flags,
      constraint_indicator_flags: constraint_indicator_flags,
      level_idc: level_idc,
      temporal_id_nested: temporal_id_nested,
      num_temporal_layers: num_temporal_layers,
      chroma_format_idc: chroma_format_idc,
      bit_depth_luma_minus8: bit_depth_luma_minus8,
      bit_depth_chroma_minus8: bit_depth_chroma_minus8,
      nalu_length_size: length_size_minus_one + 1
    }
  end

  def parse(_data), do: {:error, :unknown_pattern}

  @doc """
  Serializes a DCR
  """
  @spec serialize(t()) :: binary()
  def serialize(%__MODULE__{} = dcr) do
    <<1, dcr.profile_space::2, dcr.tier_flag::1, dcr.profile_idc::5,
      dcr.profile_compatibility_flags::32, dcr.constraint_indicator_flags::48, dcr.level_idc,
      0b1111::4, 0::12, 0b111111::6, 0::2, 0b111111::6, dcr.chroma_format_idc::2, 0b11111::5,
      dcr.bit_depth_luma_minus8::3, 0b11111::5, dcr.bit_depth_chroma_minus8::3, 0::18,
      dcr.num_temporal_layers::3, dcr.temporal_id_nested::1, dcr.nalu_length_size - 1::2-integer,
      3::8, encode_parameter_sets(dcr.vpss, 32)::binary,
      encode_parameter_sets(dcr.spss, 33)::binary, encode_parameter_sets(dcr.ppss, 34)::binary>>
  end

  defp parse_pss(<<_reserved::2, type::6, num_of_pss::16, rest::bitstring>>, type) do
    do_parse_array(num_of_pss, rest)
  end

  defp do_parse_array(amount, rest, acc \\ [])
  defp do_parse_array(0, rest, acc), do: {Enum.reverse(acc), rest}

  defp do_parse_array(remaining, <<size::16, data::binary-size(size), rest::bitstring>>, acc),
    do: do_parse_array(remaining - 1, rest, [data | acc])

  defp encode_parameter_sets(pss, nalu_type) do
    <<2::2, nalu_type::6, length(pss)::16>> <>
      Enum.map_join(pss, &<<byte_size(&1)::16-integer, &1::binary>>)
  end
end
