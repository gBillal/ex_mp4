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

    assert ExMP4.Box.serialize(box) |> IO.iodata_to_binary() == ipcm
  end
end
