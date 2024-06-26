defmodule ExMP4.WriterTest do
  @moduledoc false

  use ExUnit.Case

  alias ExMP4.{Sample, Track, Writer}

  @moduletag :tmp_dir

  @dcr <<1, 34, 32, 0, 0, 0, 144, 0, 0, 0, 0, 0, 153, 240, 0, 252, 253, 250, 250, 0, 0, 15, 3,
         160, 0, 1, 0, 33, 64, 1, 12, 1, 255, 255, 34, 32, 0, 0, 3, 0, 144, 0, 0, 3, 0, 0, 3, 0,
         153, 24, 130, 64, 192, 0, 0, 250, 64, 0, 23, 112, 58, 161, 0, 1, 0, 61, 66, 1, 1, 34, 32,
         0, 0, 3, 0, 144, 0, 0, 3, 0, 0, 3, 0, 153, 160, 1, 224, 32, 2, 28, 77, 177, 136, 38, 73,
         10, 84, 188, 5, 168, 72, 128, 77, 178, 128, 0, 1, 244, 128, 0, 46, 224, 120, 243, 4, 27,
         128, 2, 250, 240, 0, 95, 94, 248, 152, 241, 232, 162, 0, 1, 0, 8, 68, 1, 193, 114, 244,
         146, 251, 100>>

  @video_track Track.new(
                 type: :video,
                 media: :h265,
                 priv_data: @dcr,
                 timescale: 2000,
                 width: 1080,
                 height: 720
               )

  @audio_track Track.new(
                 type: :audio,
                 media: :aac,
                 priv_data: <<0, 0, 1, 3, 2>>,
                 timescale: 48_000,
                 sample_rate: 48_000,
                 channels: 2
               )

  @video_payload <<1::40-integer-unit(8)>>
  @audio_payload <<0::10-integer-unit(8)>>

  test "write mp4", %{tmp_dir: tmp_dir} do
    filepath = Path.join(tmp_dir, "out.mp4")
    assert {:ok, writer} = Writer.new(filepath)

    writer = Writer.write_header(writer, major_brand: "iso2", compatible_brands: ["isom", "mp41"])
    writer = Writer.add_tracks(writer, [@video_track, @audio_track])

    video_sample_1 =
      Sample.new(track_id: 1, dts: 0, pts: 2000, sync?: true, payload: @video_payload)

    video_sample_2 = Sample.new(track_id: 1, dts: 1000, pts: 4000, payload: @video_payload)
    video_sample_3 = Sample.new(track_id: 1, dts: 2000, pts: 5000, payload: @video_payload)
    video_sample_4 = Sample.new(track_id: 1, dts: 3000, pts: 3000, payload: @video_payload)

    video_sample_5 =
      Sample.new(track_id: 1, dts: 5000, pts: 7000, sync?: true, payload: @video_payload)

    audio_sample_1 = Sample.new(track_id: 2, dts: 0, pts: 0, payload: @audio_payload)
    audio_sample_2 = Sample.new(track_id: 2, dts: 24_000, pts: 24_000, payload: @audio_payload)
    audio_sample_3 = Sample.new(track_id: 2, dts: 48_000, pts: 48_000, payload: @audio_payload)
    audio_sample_4 = Sample.new(track_id: 2, dts: 70_000, pts: 70_000, payload: @audio_payload)

    assert :ok =
             Writer.write_sample(writer, video_sample_1)
             |> Writer.write_sample(video_sample_2)
             |> Writer.write_sample(video_sample_3)
             |> Writer.write_sample(video_sample_4)
             |> Writer.write_sample(video_sample_5)
             |> Writer.write_sample(audio_sample_1)
             |> Writer.write_sample(audio_sample_2)
             |> Writer.write_sample(audio_sample_3)
             |> Writer.write_sample(audio_sample_4)
             |> Writer.write_trailer()

    assert {:ok, reader} = ExMP4.Reader.new(filepath)

    assert reader.major_brand == "iso2"
    assert reader.compatible_brands == ["isom", "mp41"]
    assert reader.duration == 3500
    assert reader.timescale == 1000

    video_track = Enum.find(ExMP4.Reader.tracks(reader), &(&1.type == :video))
    audio_track = Enum.find(ExMP4.Reader.tracks(reader), &(&1.type == :audio))

    refute is_nil(video_track)
    refute is_nil(audio_track)

    assert %{
             id: 1,
             media: :h265,
             priv_data: %ExMP4.Codec.Hevc{},
             width: 1080,
             height: 720,
             timescale: 2000,
             sample_count: 5
           } = video_track

    assert %{
             id: 2,
             media: :aac,
             priv_data: <<0, 0, 1, 3, 2>>,
             width: nil,
             height: nil,
             timescale: 48_000,
             channels: 2,
             sample_rate: 48_000,
             sample_count: 4
           } = audio_track

    expected_result = [
      {0, 2000, true},
      {1000, 4000, false},
      {2000, 5000, false},
      {3000, 3000, false},
      {5000, 7000, true}
    ]

    for {idx, {dts, pts, sync?}} <- Enum.with_index(expected_result) do
      assert %Sample{
               track_id: video_track.id,
               dts: dts,
               pts: pts,
               sync?: sync?,
               payload: @video_payload
             } == ExMP4.Reader.read_sample(reader, video_track.id, idx)
    end

    expected_result = [{0, 2000}, {24_000, 24_000}, {48_000, 48_000}, {70_000, 70_000}]

    for {idx, {dts, pts}} <- Enum.with_index(expected_result) do
      assert %Sample{dts: ^dts, pts: ^pts, payload: @audio_payload} =
               ExMP4.Reader.read_sample(reader, audio_track.id, idx)
    end

    assert :ok = ExMP4.Reader.close(reader)
  end

  test "fast start", %{tmp_dir: tmp_dir} do
    filepath = Path.join(tmp_dir, "out.mp4")
    assert {:ok, writer} = Writer.new(filepath, fast_start: true)

    writer = Writer.write_header(writer)
    writer = Writer.add_track(writer, @video_track)

    video_sample_1 =
      Sample.new(
        track_id: 1,
        dts: 0,
        pts: 2000,
        sync?: true,
        payload: @video_payload
      )

    assert :ok =
             writer
             |> Writer.write_sample(video_sample_1)
             |> Writer.write_trailer()

    assert {:ok, data} = File.read(filepath)
    assert <<_ftyp::binary-size(32), _moov_size::binary-size(4), "moov", _rest::binary>> = data
  end
end
