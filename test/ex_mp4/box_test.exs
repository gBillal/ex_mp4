defmodule ExMP4.BoxTest do
  @moduledoc false

  use ExUnit.Case

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
end
