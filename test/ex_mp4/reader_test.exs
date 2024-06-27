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

    assert Reader.duration(reader, 500) == 31
    assert Reader.duration(reader, :microsecond) == 62_000

    assert [video_track, audio_track] = Reader.tracks(reader)

    assert %Track{
             id: 1,
             type: :video,
             media: :h264,
             media_tag: :avc1,
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
             payload: payload
           } = Reader.read_sample(reader, 1, 0)

    assert byte_size(payload) == 751

    assert %Sample{dts: 0, pts: 0, payload: payload} = Reader.read_sample(reader, 2, 0)
    assert byte_size(payload) == 179

    assert %Sample{dts: 1024, pts: 1024, payload: payload} = Reader.read_sample(reader, 2, 1)
    assert byte_size(payload) == 180

    assert %Sample{dts: 2048, pts: 2048, payload: payload} = Reader.read_sample(reader, 2, 2)
    assert byte_size(payload) == 160

    assert :ok = Reader.close(reader)
  end

  test "read fragmented mp4 file" do
    assert {:ok, reader} = Reader.new("test/fixtures/fragmented.mp4")

    assert reader.major_brand == "isom"
    assert reader.major_brand_version == 1
    assert reader.compatible_brands == ["isom", "iso2", "avc1", "mp41"]
    assert reader.duration == 107
    assert reader.timescale == 1_000

    assert Reader.duration(reader, 500) == 54
    assert Reader.duration(reader, :microsecond) == 107_000

    assert [video_track, audio_track] = Reader.tracks(reader) |> Enum.sort_by(& &1.id)

    assert %Track{
             id: 1,
             type: :video,
             media: :h264,
             media_tag: :avc1,
             duration: 3,
             timescale: 30,
             width: 480,
             height: 270,
             sample_count: 3
           } =
             video_track

    assert %Track{
             id: 2,
             type: :audio,
             media: :aac,
             duration: 5_120,
             timescale: 48_000,
             sample_count: 5,
             sample_rate: 48_000,
             channels: 2
           } =
             audio_track

    samples = for id <- 0..2, do: Reader.read_sample(reader, 1, id)

    assert Enum.map(samples, & &1.dts) == [0, 1, 2]
    assert Enum.map(samples, & &1.pts) == [0, 1, 2]
    assert Enum.map(samples, & &1.sync?) == [true, false, false]
    assert Enum.map(samples, &byte_size(&1.payload)) == [13_740, 276, 219]

    samples = for id <- 0..4, do: Reader.read_sample(reader, 2, id)

    assert Enum.map(samples, & &1.dts) == [0, 1024, 2048, 3072, 4096]
    assert Enum.map(samples, & &1.pts) == [0, 1024, 2048, 3072, 4096]
    assert Enum.all?(Enum.map(samples, & &1.sync?))
    assert Enum.map(samples, &byte_size(&1.payload)) == [299, 298, 299, 299, 298]

    assert :ok = Reader.close(reader)
  end
end
