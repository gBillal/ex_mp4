defmodule ExMP4.FWriterTest do
  @moduledoc false

  use ExUnit.Case

  import ExMP4.Support.Utils

  alias ExMP4.{FWriter, Sample}

  @moduletag :tmp_dir

  @video_payload <<1::40-integer-unit(8)>>
  @audio_payload <<0::10-integer-unit(8)>>

  @video_samples [
    {0, 2000, 1000, true},
    {1000, 4000, 1000, false},
    {2000, 5000, 1000, false},
    {3000, 3000, 2000, false},
    {5000, 7000, 2000, true}
  ]

  @audio_samples [
    {0, 0, 24_000},
    {24_000, 24_000, 24_000},
    {48_000, 48_000, 22_000},
    {70_000, 70_000, 22_000}
  ]

  test "write fragmented mp4", %{tmp_dir: tmp_dir} do
    filepath = Path.join(tmp_dir, "out.mp4")
    assert {:ok, writer} = FWriter.new(filepath, [video_track(), audio_track()])

    assert :ok =
             FWriter.create_fragment(writer)
             |> FWriter.write_sample(video_sample(0))
             |> FWriter.write_sample(video_sample(1))
             |> FWriter.write_sample(video_sample(2))
             |> FWriter.write_sample(audio_sample(0))
             |> FWriter.write_sample(audio_sample(1))
             |> FWriter.flush_fragment()
             |> FWriter.create_fragment()
             |> FWriter.write_sample(video_sample(3))
             |> FWriter.write_sample(video_sample(4))
             |> FWriter.write_sample(audio_sample(2))
             |> FWriter.write_sample(audio_sample(3))
             |> FWriter.flush_fragment()
             |> FWriter.close()

    assert {:ok, reader} = ExMP4.Reader.new(filepath)

    assert reader.major_brand == "mp42"
    assert reader.compatible_brands == ["mp42", "mp41", "isom", "avc1"]
    assert reader.duration == 3500
    assert reader.timescale == 1000
    assert reader.fragmented?

    video_track = Enum.find(ExMP4.Reader.tracks(reader), &(&1.type == :video))
    audio_track = Enum.find(ExMP4.Reader.tracks(reader), &(&1.type == :audio))

    refute is_nil(video_track)
    refute is_nil(audio_track)

    for idx <- 0..4 do
      assert video_sample(idx) == ExMP4.Reader.read_sample(reader, video_track.id, idx)
    end

    for idx <- 0..3 do
      assert audio_sample(idx) == ExMP4.Reader.read_sample(reader, audio_track.id, idx)
    end

    assert :ok = ExMP4.Reader.close(reader)
  end

  defp video_sample(num) do
    {dts, pts, duration, sync?} = Enum.at(@video_samples, num)

    Sample.new(
      track_id: 1,
      dts: dts,
      pts: pts,
      duration: duration,
      sync?: sync?,
      payload: @video_payload
    )
  end

  defp audio_sample(num) do
    {dts, pts, duration} = Enum.at(@audio_samples, num)

    Sample.new(
      track_id: 2,
      dts: dts,
      pts: pts,
      duration: duration,
      sync?: true,
      payload: @audio_payload
    )
  end
end
