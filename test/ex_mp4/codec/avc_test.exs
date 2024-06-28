defmodule ExMP4.Codec.AvcTest do
  @moduledoc false

  use ExUnit.Case

  alias ExMP4.Codec.Avc

  @dcr %ExMP4.Codec.Avc{
    spss: [
      <<103, 77, 64, 30, 217, 0, 160, 61, 176, 17, 0, 0, 3, 3, 233, 0, 0, 187, 128, 15, 22, 46,
        72>>
    ],
    ppss: [<<104, 235, 143, 32>>],
    avc_profile_indication: 77,
    avc_level: 30,
    profile_compatibility: 64,
    nalu_length_size: 4
  }

  @serialized_dcr <<1, 77, 64, 30, 255, 225, 0, 23, 103, 77, 64, 30, 217, 0, 160, 61, 176, 17, 0,
                    0, 3, 3, 233, 0, 0, 187, 128, 15, 22, 46, 72, 1, 0, 4, 104, 235, 143, 32>>

  test "new" do
    assert Avc.new(@dcr.spss, @dcr.ppss) == @dcr
  end

  test "serialize" do
    assert Avc.serialize(@dcr) == @serialized_dcr
  end

  test "parse" do
    assert Avc.parse(@serialized_dcr) == @dcr
  end
end
