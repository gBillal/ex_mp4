defmodule ExMP4.Box.Vpcc do
  @moduledoc """
  A module representing an `vpcC` box.
  """

  @type t() :: %__MODULE__{
          version: integer(),
          flags: integer(),
          profile: integer(),
          level: integer(),
          bit_depth: integer(),
          chroma_subsampling: integer(),
          video_full_range_flag: integer(),
          colour_primaries: integer(),
          transfer_characteristics: integer(),
          matrix_coefficients: integer(),
          codec_initialization_data_size: integer(),
          codec_initialization_data: list()
        }

  defstruct [
    :profile,
    :level,
    :bit_depth,
    :chroma_subsampling,
    :video_full_range_flag,
    :colour_primaries,
    :transfer_characteristics,
    :matrix_coefficients,
    version: 1,
    flags: 0,
    codec_initialization_data_size: 0,
    codec_initialization_data: []
  ]

  defimpl ExMP4.Box do
    def size(_box), do: ExMP4.full_box_header_size() + 8

    def parse(
          box,
          <<1::8, 0::24, profile::8, level::8, bit_depth::4, chroma::3, full_range::1,
            colour_primaries::8, transfer_characteristics::8, matrix_coefficients::8, 0::16>>
        ) do
      %{
        box
        | profile: profile,
          level: level,
          chroma_subsampling: chroma,
          bit_depth: bit_depth,
          video_full_range_flag: full_range,
          colour_primaries: colour_primaries,
          transfer_characteristics: transfer_characteristics,
          matrix_coefficients: matrix_coefficients
      }
    end

    def serialize(box) do
      <<size(box)::32, "vpcC", box.version, box.flags::24, box.profile, box.level,
        box.bit_depth::4, box.chroma_subsampling::3, box.video_full_range_flag::1,
        box.colour_primaries, box.transfer_characteristics, box.matrix_coefficients, 0::16>>
    end
  end
end
