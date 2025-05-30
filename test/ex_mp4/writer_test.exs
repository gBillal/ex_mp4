defmodule ExMP4.WriterTest do
  @moduledoc false

  use ExUnit.Case

  import ExMP4.Support.Utils

  alias ExMP4.{Sample, Writer}

  @moduletag :tmp_dir

  @video_payload <<1::40-integer-unit(8)>>
  @audio_payload <<0::10-integer-unit(8)>>

  test "write mp4", %{tmp_dir: tmp_dir} do
    filepath = Path.join(tmp_dir, "out.mp4")
    assert {:ok, writer} = Writer.new(filepath)

    writer = Writer.write_header(writer, major_brand: "iso2", compatible_brands: ["isom", "mp41"])
    writer = Writer.add_tracks(writer, [video_track(), audio_track()])

    assert :ok =
             video_samples()
             |> Enum.concat(audio_samples())
             |> Enum.reduce(writer, &Writer.write_sample(&2, &1))
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
             priv_data: %ExMP4.Box.Hvcc{},
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

    for {sample, idx} <- Enum.with_index(video_samples()) do
      assert sample == ExMP4.Reader.read_sample(reader, video_track.id, idx)
    end

    for {sample, idx} <- Enum.with_index(audio_samples()) do
      assert sample == ExMP4.Reader.read_sample(reader, audio_track.id, idx)
    end

    assert :ok = ExMP4.Reader.close(reader)
  end

  test "fast start", %{tmp_dir: tmp_dir} do
    filepath = Path.join(tmp_dir, "out.mp4")
    assert {:ok, writer} = Writer.new(filepath, fast_start: true)

    writer = Writer.write_header(writer)
    writer = Writer.add_track(writer, video_track())

    video_sample_1 =
      Sample.new(
        track_id: 1,
        dts: 0,
        pts: 2000,
        duration: 1000,
        sync?: true,
        payload: @video_payload
      )

    assert :ok =
             [video_sample_1]
             |> Enum.into(writer)
             |> Writer.write_trailer()

    assert {:ok, data} = File.read(filepath)
    assert <<_ftyp::binary-size(32), _moov_size::binary-size(4), "moov", _rest::binary>> = data
  end

  defp video_samples do
    [
      {0, 2000, 1000, true},
      {1000, 4000, 1000, false},
      {2000, 5000, 1000, false},
      {3000, 3000, 2000, false},
      {5000, 7000, 2000, true}
    ]
    |> Enum.map(fn {dts, pts, duration, sync?} ->
      Sample.new(
        track_id: 1,
        dts: dts,
        pts: pts,
        duration: duration,
        sync?: sync?,
        payload: @video_payload
      )
    end)
  end

  defp audio_samples do
    [
      {0, 0, 24_000},
      {24_000, 24_000, 24_000},
      {48_000, 48_000, 22_000},
      {70_000, 70_000, 22_000}
    ]
    |> Enum.map(fn {dts, pts, duration} ->
      Sample.new(
        track_id: 2,
        dts: dts,
        pts: pts,
        duration: duration,
        sync?: true,
        payload: @audio_payload
      )
    end)
  end
end
