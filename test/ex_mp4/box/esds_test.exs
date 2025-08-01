defmodule ExMP4.Box.EsdsTest do
  use ExUnit.Case, async: true

  alias MediaCodecs.MPEG4.AudioSpecificConfig
  alias ExMP4.Box.Esds

  test "get audio specific config" do
    audio_specific_config = <<17, 144>>
    assert %Esds{} = esds = Esds.new(audio_specific_config)
    assert Esds.audio_specific_config(esds) == audio_specific_config
  end
end
