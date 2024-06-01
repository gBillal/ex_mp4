defmodule ExMP4.ReaderTest do
  @moduledoc false

  use ExUnit.Case

  alias ExMP4.{Reader, Sample, Track}

  test "read mp4 file" do
    assert {:ok, reader} = Reader.new("test/fixtures/minimal.mp4")

    assert reader.major_brand == "isom"
    assert reader.major_brand_version == 512
    assert reader.compatible_brands == ["isom", "iso2", "avc1", "mp41"]
    assert reader.duration == 62
    assert reader.timescale == 1_000

    assert [video_track, audio_track] = Reader.tracks(reader)

    assert %Track{
             id: 1,
             type: :video,
             media: :h264,
             duration: 512,
             timescale: 12_800,
             width: 320,
             height: 240,
             sample_count: 1
           } =
             video_track

    assert %Track{
             id: 2,
             type: :audio,
             media: :aac,
             duration: 2_944,
             timescale: 48_000,
             sample_count: 3,
             sample_rate: 48_000,
             channels: 2
           } =
             audio_track

    assert %Sample{
             pts: 0,
             dts: 0,
             sync?: true,
             content: content
           } = Reader.read_sample(reader, 1, 0)

    assert byte_size(content) == 751

    assert %Sample{dts: 0, pts: 0, content: content} = Reader.read_sample(reader, 2, 0)
    assert byte_size(content) == 179

    assert %Sample{dts: 1024, pts: 1024, content: content} = Reader.read_sample(reader, 2, 1)
    assert byte_size(content) == 180

    assert %Sample{dts: 2048, pts: 2048, content: content} = Reader.read_sample(reader, 2, 2)
    assert byte_size(content) == 160

    assert :ok = Reader.close(reader)
  end
end
