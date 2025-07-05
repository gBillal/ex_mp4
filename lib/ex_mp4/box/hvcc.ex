defmodule ExMP4.Box.Hvcc do
  @moduledoc """
  A module representing an `hvcC` box.
  """

  @type t() :: %__MODULE__{
          vps: [binary()],
          sps: [binary()],
          pps: [binary()],
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

  defstruct [
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
    nalu_length_size: 4,
    vps: [],
    sps: [],
    pps: []
  ]

  if Code.ensure_compiled!(MediaCodecs) do
    @doc """
    Creates a new `hvcC` box from parameter sets.

    Only available if [MediaCodecs](https://hex.pm/packages/media_codecs) is installed.
    """
    @spec new([binary()], [binary()], [binary()], non_neg_integer()) :: t()
    def new(vps, sps, pps, nalu_length_size \\ 4) do
      parsed_sps = MediaCodecs.H265.NALU.SPS.parse(List.first(sps))

      <<constraint_indicator_flags::48>> =
        <<parsed_sps.progressive_source_flag::1, parsed_sps.interlaced_source_flag::1,
          parsed_sps.non_packed_constraint_flag::1, parsed_sps.frame_only_constraint_flag::1,
          0::44>>

      %__MODULE__{
        vps: vps,
        sps: sps,
        pps: pps,
        profile_space: parsed_sps.profile_space,
        tier_flag: parsed_sps.tier_flag,
        profile_idc: parsed_sps.profile_idc,
        profile_compatibility_flags: parsed_sps.profile_compatibility_flag,
        constraint_indicator_flags: constraint_indicator_flags,
        level_idc: parsed_sps.level_idc,
        chroma_format_idc: parsed_sps.chroma_format_idc,
        bit_depth_chroma_minus8: parsed_sps.bit_depth_chroma_minus8,
        bit_depth_luma_minus8: parsed_sps.bit_depth_luma_minus8,
        temporal_id_nested: parsed_sps.temporal_id_nesting_flag,
        num_temporal_layers: parsed_sps.max_sub_layers_minus1,
        nalu_length_size: nalu_length_size
      }
    end
  end

  defimpl ExMP4.Box do
    def size(box) do
      vps_size = Enum.map(box.vps, &(byte_size(&1) + 2)) |> Enum.sum()
      sps_size = Enum.map(box.sps, &(byte_size(&1) + 2)) |> Enum.sum()
      pps_size = Enum.map(box.pps, &(byte_size(&1) + 2)) |> Enum.sum()
      # header size + size of elements + parameter sets size + parameter sets header size
      ExMP4.header_size() + 23 + vps_size + sps_size + pps_size + 9
    end

    def parse(
          box,
          <<1::8, profile_space::2, tier_flag::1, profile_idc::5, profile_compatibility_flags::32,
            constraint_indicator_flags::48, level_idc::8, 0b1111::4,
            _min_spatial_segmentation_idc::12, 0b111111::6, _parallelism_type::2, 0b111111::6,
            chroma_format_idc::2, 0b11111::5, bit_depth_luma_minus8::3, 0b11111::5,
            bit_depth_chroma_minus8::3, _avg_frame_rate::16, _constant_frame_rate::2,
            num_temporal_layers::3, temporal_id_nested::1, length_size_minus_one::2-integer,
            num_of_arrays::8, rest::binary>>
        ) do
      {vps, sps, pps} =
        if num_of_arrays > 0 do
          {vps, rest} = parse_pss(rest, 32)
          {sps, rest} = parse_pss(rest, 33)
          {pps, _rest} = parse_pss(rest, 34)

          {vps, sps, pps}
        else
          {[], [], []}
        end

      %{
        box
        | vps: vps,
          sps: sps,
          pps: pps,
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

    def serialize(box) do
      <<size(box)::32, "hvcC", 1, box.profile_space::2, box.tier_flag::1, box.profile_idc::5,
        box.profile_compatibility_flags::32, box.constraint_indicator_flags::48, box.level_idc,
        0b1111::4, 0::12, 0b111111::6, 0::2, 0b111111::6, box.chroma_format_idc::2, 0b11111::5,
        box.bit_depth_luma_minus8::3, 0b11111::5, box.bit_depth_chroma_minus8::3, 0::18,
        box.num_temporal_layers::3, box.temporal_id_nested::1,
        box.nalu_length_size - 1::2-integer, 3::8, encode_parameter_sets(box.vps, 32)::binary,
        encode_parameter_sets(box.sps, 33)::binary, encode_parameter_sets(box.pps, 34)::binary>>
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
end
