defmodule ExMP4.Codec.HevcTest do
  @moduledoc false

  use ExUnit.Case

  alias ExMP4.Codec.Hevc

  @dcr %Hevc{
    vpss: [
      <<64, 1, 12, 1, 255, 255, 34, 32, 0, 0, 3, 0, 144, 0, 0, 3, 0, 0, 3, 0, 153, 24, 130, 64,
        192, 0, 0, 250, 64, 0, 23, 112, 58>>
    ],
    spss: [
      <<66, 1, 1, 34, 32, 0, 0, 3, 0, 144, 0, 0, 3, 0, 0, 3, 0, 153, 160, 1, 224, 32, 2, 28, 77,
        177, 136, 38, 73, 10, 84, 188, 5, 168, 72, 128, 77, 178, 128, 0, 1, 244, 128, 0, 46, 224,
        120, 243, 4, 27, 128, 2, 250, 240, 0, 95, 94, 248, 152, 241, 232>>
    ],
    ppss: [<<68, 1, 193, 114, 244, 146, 251, 100>>],
    profile_space: 0,
    tier_flag: 1,
    profile_idc: 2,
    profile_compatibility_flags: 536_870_912,
    constraint_indicator_flags: 158_329_674_399_744,
    level_idc: 153,
    temporal_id_nested: 1,
    num_temporal_layers: 1,
    chroma_format_idc: 1,
    bit_depth_luma_minus8: 2,
    bit_depth_chroma_minus8: 2,
    nalu_length_size: 4
  }

  @serialized_dcr <<1, 34, 32, 0, 0, 0, 144, 0, 0, 0, 0, 0, 153, 240, 0, 252, 253, 250, 250, 0, 0,
                    15, 3, 160, 0, 1, 0, 33, 64, 1, 12, 1, 255, 255, 34, 32, 0, 0, 3, 0, 144, 0,
                    0, 3, 0, 0, 3, 0, 153, 24, 130, 64, 192, 0, 0, 250, 64, 0, 23, 112, 58, 161,
                    0, 1, 0, 61, 66, 1, 1, 34, 32, 0, 0, 3, 0, 144, 0, 0, 3, 0, 0, 3, 0, 153, 160,
                    1, 224, 32, 2, 28, 77, 177, 136, 38, 73, 10, 84, 188, 5, 168, 72, 128, 77,
                    178, 128, 0, 1, 244, 128, 0, 46, 224, 120, 243, 4, 27, 128, 2, 250, 240, 0,
                    95, 94, 248, 152, 241, 232, 162, 0, 1, 0, 8, 68, 1, 193, 114, 244, 146, 251,
                    100>>

  test "serialize" do
    assert Hevc.serialize(@dcr) == @serialized_dcr
  end

  test "parse" do
    assert Hevc.parse(@serialized_dcr) == @dcr
  end
end
