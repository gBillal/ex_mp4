defmodule ExMP4.FWriterTest do
  @moduledoc false

  use ExUnit.Case

  import ExMP4.Support.Utils

  alias ExMP4.{FWriter, Sample}

  @moduletag :tmp_dir

  @video_payload <<1::40-integer-unit(8)>>
  @audio_payload <<0::10-integer-unit(8)>>

  test "write fragmented mp4", %{tmp_dir: tmp_dir} do
    filepath = Path.join(tmp_dir, "out.mp4")
    assert {:ok, writer} = FWriter.new(filepath, [video_track(), audio_track()])

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
             FWriter.create_fragment(writer)
             |> FWriter.write_sample(video_sample_1)
             |> FWriter.write_sample(video_sample_2)
             |> FWriter.write_sample(video_sample_3)
             |> FWriter.write_sample(audio_sample_1)
             |> FWriter.write_sample(audio_sample_2)
             |> FWriter.flush_fragment()
             |> FWriter.create_fragment()
             |> FWriter.write_sample(video_sample_4)
             |> FWriter.write_sample(video_sample_5)
             |> FWriter.write_sample(audio_sample_3)
             |> FWriter.write_sample(audio_sample_4)
             |> FWriter.flush_fragment()
             |> FWriter.close()

    assert {:ok, reader} = ExMP4.Reader.new(filepath)

    assert reader.major_brand == "isom"
    assert reader.compatible_brands == ["isom", "iso2", "avc1", "mp41", "iso6"]
    assert reader.duration == 3500
    assert reader.timescale == 1000
    assert reader.fragmented?

    video_track = Enum.find(ExMP4.Reader.tracks(reader), &(&1.type == :video))
    audio_track = Enum.find(ExMP4.Reader.tracks(reader), &(&1.type == :audio))

    refute is_nil(video_track)
    refute is_nil(audio_track)

    assert length(video_track.frag_sample_table.moofs) == 2
    assert length(audio_track.frag_sample_table.moofs) == 2

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
end
