defmodule ExMP4.TrackTest do
  @moduledoc false

  use ExUnit.Case

  test "track" do
    reader = ExMP4.Reader.new!("test/fixtures/minimal.mp4")

    video_track = Enum.find(ExMP4.Reader.tracks(reader), &(&1.type == :video))
    audio_track = Enum.find(ExMP4.Reader.tracks(reader), &(&1.type == :audio))

    assert ExMP4.Track.duration(video_track) == 40
    assert ExMP4.Track.duration(video_track, 500) == 20
    assert ExMP4.Track.bitrate(video_track) == 150_200
    assert ExMP4.Track.fps(video_track) == 25.0

    assert ExMP4.Track.duration(audio_track) == 61
    assert ExMP4.Track.bitrate(audio_track) == 68_065
    assert ExMP4.Track.fps(audio_track) == 0

    ExMP4.Reader.close(reader)
  end
end
