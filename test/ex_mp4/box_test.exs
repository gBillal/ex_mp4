defmodule ExMP4.BoxTest do
  @moduledoc false

  use ExUnit.Case

  alias ExMP4.Box.{Ipcm, Pcmc}

  test "parse and serialize" do
    assert {:ok, moov} = File.read("test/fixtures/moov.bin")
    assert <<812_644::32, "moov", rest::binary>> = moov

    assert box = ExMP4.Box.parse(%ExMP4.Box.Moov{}, rest)
    assert ExMP4.Box.serialize(box) |> IO.iodata_to_binary() == moov
  end

  test "parse and serialize mvex" do
    assert {:ok, mvex} = File.read("test/fixtures/mvex.bin")
    assert <<88::32, "mvex", rest::binary>> = mvex

    assert box = ExMP4.Box.parse(%ExMP4.Box.Mvex{}, rest)
    assert ExMP4.Box.serialize(box) |> IO.iodata_to_binary() == mvex
  end

  test "parse and serialize ipcm" do
    ipcm =
      <<0, 0, 0, 50, 105, 112, 99, 109, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0,
        24, 0, 0, 0, 0, 187, 128, 0, 0, 0, 0, 0, 14, 112, 99, 109, 67, 0, 0, 0, 0, 0, 24>>

    assert %Ipcm{
             channel_count: 1,
             sample_rate: {48_000, 0},
             sample_size: 24,
             pcmC: %Pcmc{format_flags: 0, pcm_sample_size: 24}
           } = box = ExMP4.Box.parse(%Ipcm{}, :binary.part(ipcm, 8, byte_size(ipcm) - 8))

    assert ExMP4.Box.size(box) == 50
    assert ExMP4.Box.serialize(box) |> IO.iodata_to_binary() == ipcm
  end

  test "serialize and parse sidx" do
    sidx = %ExMP4.Box.Sidx{
      version: 0,
      flags: 0,
      reference_id: 1,
      timescale: 16_000,
      earliest_presentation_time: 0,
      first_offset: 0,
      entries: [
        %{
          reference_type: 1,
          referenced_size: 0x100,
          subsegment_duration: 32_000,
          starts_with_sap: 1,
          sap_type: 1,
          sap_delta_time: 0
        },
        %{
          reference_type: 1,
          referenced_size: 0x150,
          subsegment_duration: 48_000,
          starts_with_sap: 1,
          sap_type: 1,
          sap_delta_time: 0
        }
      ]
    }

    expected =
      <<0, 0, 0, 56, 115, 105, 100, 120, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 62, 128, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 2, 128, 0, 1, 0, 0, 0, 125, 0, 144, 0, 0, 0, 128, 0, 1, 80, 0, 0, 187, 128,
        144, 0, 0, 0>>

    assert ExMP4.Box.size(sidx) == 56
    assert ExMP4.Box.serialize(sidx) |> IO.iodata_to_binary() == expected
    assert ExMP4.Box.parse(%ExMP4.Box.Sidx{}, :binary.part(expected, 8, 48)) == sidx
  end

  test "serialize and parse styp" do
    styp = %ExMP4.Box.Styp{
      major_brand: "isom",
      minor_version: 512,
      compatible_brands: ["isom", "iso6"]
    }

    expected =
      <<0, 0, 0, 24, 115, 116, 121, 112, 105, 115, 111, 109, 0, 0, 2, 0, 105, 115, 111, 109, 105,
        115, 111, 54>>

    assert ExMP4.Box.size(styp) == 24
    assert ExMP4.Box.serialize(styp) |> IO.iodata_to_binary() == expected
    assert ExMP4.Box.parse(%ExMP4.Box.Styp{}, :binary.part(expected, 8, 16)) == styp
  end
end
