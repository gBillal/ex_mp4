defmodule ExMP4.FWriterTest do
  @moduledoc false

  use ExUnit.Case

  import ExMP4.Support.Utils

  alias ExMP4.{FWriter, Sample}

  @moduletag :tmp_dir

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

    video_samples = for idx <- 0..4, do: video_sample(idx)
    audio_samples = for idx <- 0..3, do: audio_sample(idx)

    assert :ok =
             FWriter.create_fragment(writer)
             |> FWriter.write_sample(Enum.at(video_samples, 0))
             |> FWriter.write_sample(Enum.at(video_samples, 1))
             |> FWriter.write_sample(Enum.at(video_samples, 2))
             |> FWriter.write_sample(Enum.at(audio_samples, 0))
             |> FWriter.write_sample(Enum.at(audio_samples, 1))
             |> FWriter.flush_fragment()
             |> FWriter.create_fragment()
             |> FWriter.write_sample(Enum.at(video_samples, 3))
             |> FWriter.write_sample(Enum.at(video_samples, 4))
             |> FWriter.write_sample(Enum.at(audio_samples, 2))
             |> FWriter.write_sample(Enum.at(audio_samples, 3))
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
      assert Enum.at(video_samples, idx) == ExMP4.Reader.read_sample(reader, video_track.id, idx)
    end

    for idx <- 0..3 do
      assert Enum.at(audio_samples, idx) == ExMP4.Reader.read_sample(reader, audio_track.id, idx)
    end

    assert :ok = ExMP4.Reader.close(reader)
  end

  test "write fragmented mp4 (base is moof)", %{tmp_dir: tmp_dir} do
    filepath = Path.join(tmp_dir, "out.mp4")

    assert {:ok, writer} =
             FWriter.new(filepath, [video_track(), audio_track()], moof_base_offset: true)

    video_samples = for idx <- 0..4, do: video_sample(idx)
    audio_samples = for idx <- 0..3, do: audio_sample(idx)

    assert :ok =
             FWriter.create_fragment(writer)
             |> FWriter.write_sample(Enum.at(video_samples, 0))
             |> FWriter.write_sample(Enum.at(video_samples, 1))
             |> FWriter.write_sample(Enum.at(video_samples, 2))
             |> FWriter.write_sample(Enum.at(audio_samples, 0))
             |> FWriter.write_sample(Enum.at(audio_samples, 1))
             |> FWriter.flush_fragment()
             |> FWriter.create_fragment()
             |> FWriter.write_sample(Enum.at(video_samples, 3))
             |> FWriter.write_sample(Enum.at(video_samples, 4))
             |> FWriter.write_sample(Enum.at(audio_samples, 2))
             |> FWriter.write_sample(Enum.at(audio_samples, 3))
             |> FWriter.flush_fragment()
             |> FWriter.close()

    assert {:ok, reader} = ExMP4.Reader.new(filepath)

    assert reader.major_brand == "iso5"
    assert reader.compatible_brands == ["iso6", "mp41"]
    assert reader.duration == 3500
    assert reader.timescale == 1000
    assert reader.fragmented?

    video_track = Enum.find(ExMP4.Reader.tracks(reader), &(&1.type == :video))
    audio_track = Enum.find(ExMP4.Reader.tracks(reader), &(&1.type == :audio))

    refute is_nil(video_track)
    refute is_nil(audio_track)

    for idx <- 0..4 do
      assert Enum.at(video_samples, idx) == ExMP4.Reader.read_sample(reader, video_track.id, idx)
    end

    for idx <- 0..3 do
      assert Enum.at(audio_samples, idx) == ExMP4.Reader.read_sample(reader, audio_track.id, idx)
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
      payload: :crypto.strong_rand_bytes(:rand.uniform(100) + 50)
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
      payload: :crypto.strong_rand_bytes(:rand.uniform(10) + 50)
    )
  end
end
