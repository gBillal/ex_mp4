defmodule ExMP4.Support.Utils do
  @moduledoc false

  alias ExMP4.Track

  @dcr <<1, 34, 32, 0, 0, 0, 144, 0, 0, 0, 0, 0, 153, 240, 0, 252, 253, 250, 250, 0, 0, 15, 3,
         160, 0, 1, 0, 33, 64, 1, 12, 1, 255, 255, 34, 32, 0, 0, 3, 0, 144, 0, 0, 3, 0, 0, 3, 0,
         153, 24, 130, 64, 192, 0, 0, 250, 64, 0, 23, 112, 58, 161, 0, 1, 0, 61, 66, 1, 1, 34, 32,
         0, 0, 3, 0, 144, 0, 0, 3, 0, 0, 3, 0, 153, 160, 1, 224, 32, 2, 28, 77, 177, 136, 38, 73,
         10, 84, 188, 5, 168, 72, 128, 77, 178, 128, 0, 1, 244, 128, 0, 46, 224, 120, 243, 4, 27,
         128, 2, 250, 240, 0, 95, 94, 248, 152, 241, 232, 162, 0, 1, 0, 8, 68, 1, 193, 114, 244,
         146, 251, 100>>

  @video_track Track.new(
                 id: 1,
                 type: :video,
                 media: :h265,
                 priv_data: @dcr,
                 timescale: 2000,
                 width: 1080,
                 height: 720
               )

  @audio_track Track.new(
                 id: 2,
                 type: :audio,
                 media: :aac,
                 priv_data: %ExMP4.Box.Esds{es_descriptor: <<0, 0, 1, 3, 2>>},
                 timescale: 48_000,
                 sample_rate: 48_000,
                 channels: 2
               )

  @spec video_track :: Track.t()
  def video_track, do: @video_track

  @spec audio_track :: Track.t()
  def audio_track, do: @audio_track
end
