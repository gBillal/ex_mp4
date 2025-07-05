defmodule ExMP4.Box.Avcc do
  @moduledoc """
  A module representing an `avcC` box.
  """

  @type new_opts :: [nalu_length_size: integer()]

  @type t() :: %__MODULE__{
          sps: [binary()],
          pps: [binary()],
          avc_profile_indication: non_neg_integer(),
          profile_compatibility: non_neg_integer(),
          avc_level: non_neg_integer(),
          nalu_length_size: pos_integer()
        }

  defstruct [
    :avc_profile_indication,
    :avc_level,
    :profile_compatibility,
    nalu_length_size: 4,
    sps: [],
    pps: []
  ]

  @doc """
  Creates a new `avcC` box from parameter sets.
  """
  @spec new([binary()], [binary()]) :: t()
  @spec new([binary()], [binary()], new_opts()) :: t()
  def new(sps, pps, opts \\ []) do
    <<_idc_and_type, profile, compatibility, level, _rest::binary>> = List.last(sps)

    %__MODULE__{
      sps: sps,
      pps: pps,
      avc_profile_indication: profile,
      avc_level: level,
      profile_compatibility: compatibility,
      nalu_length_size: Keyword.get(opts, :nalu_length_size, 4)
    }
  end

  defimpl ExMP4.Box do
    def size(box) do
      sps_size = Enum.map(box.sps, &(byte_size(&1) + 2)) |> Enum.sum()
      pps_size = Enum.map(box.pps, &(byte_size(&1) + 2)) |> Enum.sum()
      ExMP4.header_size() + 7 + sps_size + pps_size
    end

    def parse(
          box,
          <<1::8, avc_profile_indication::8, profile_compatibility::8, avc_level::8, 0b111111::6,
            length_size_minus_one::2, 0b111::3, rest::bitstring>>
        ) do
      {sps, rest} = parse_spss(rest)
      {pps, _rest} = parse_ppss(rest)

      %{
        box
        | sps: sps,
          pps: pps,
          avc_profile_indication: avc_profile_indication,
          profile_compatibility: profile_compatibility,
          avc_level: avc_level,
          nalu_length_size: length_size_minus_one + 1
      }
    end

    def serialize(box) do
      <<size(box)::32, "avcC", 1, box.avc_profile_indication, box.profile_compatibility,
        box.avc_level, 0b111111::6, box.nalu_length_size - 1::2-integer, 0b111::3,
        length(box.sps)::5-integer, encode_parameter_sets(box.sps)::binary,
        length(box.pps)::8-integer, encode_parameter_sets(box.pps)::binary>>
    end

    defp encode_parameter_sets(pss) do
      Enum.map_join(pss, &<<byte_size(&1)::16-integer, &1::binary>>)
    end

    defp parse_spss(<<num_of_spss::5, rest::bitstring>>) do
      do_parse_array(num_of_spss, rest)
    end

    defp parse_ppss(<<num_of_ppss::8, rest::bitstring>>), do: do_parse_array(num_of_ppss, rest)

    defp do_parse_array(amount, rest, acc \\ [])
    defp do_parse_array(0, rest, acc), do: {Enum.reverse(acc), rest}

    defp do_parse_array(remaining, <<size::16, data::binary-size(size), rest::bitstring>>, acc),
      do: do_parse_array(remaining - 1, rest, [data | acc])
  end
end
