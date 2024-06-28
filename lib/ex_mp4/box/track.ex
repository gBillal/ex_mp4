defmodule ExMP4.Box.Track do
  @moduledoc """
  A module containing a set of utilities for assembling an MPEG-4 track box.

  The track box (`trak` atom) describes a single track of a presentation. This description includes
  information like its timescale, duration, volume, media-specific data (media handlers, sample
  descriptions) as well as a sample table, which allows media players to find and interpret
  track's data in the media data box.

  For more information about the track box, refer to [ISO/IEC 14496-12](https://www.iso.org/standard/74428.html).
  """
  alias ExMP4.{Container, Box.SampleTable, Track}

  defguardp is_audio(track) when track.type == :audio

  @spec assemble(Track.t()) :: Container.t()
  def assemble(track) do
    dref =
      {:dref,
       %{
         children: [url: %{children: [], fields: %{flags: 1, version: 0}}],
         fields: %{entry_count: 1, flags: 0, version: 0}
       }}

    dinf = [dinf: %{children: [dref], fields: %{}}]

    [
      trak: %{
        children:
          track_header(track) ++
            [
              mdia: %{
                children:
                  media_handler_header(track) ++
                    handler(track) ++
                    [
                      minf: %{
                        children: media_header(track) ++ dinf ++ SampleTable.assemble(track),
                        fields: %{}
                      }
                    ],
                fields: %{}
              }
            ],
        fields: %{}
      }
    ]
  end

  defp track_header(track) do
    [
      tkhd: %{
        children: [],
        fields: %{
          alternate_group: 0,
          creation_time: 0,
          duration: track.duration,
          flags: 3,
          height: {track.height || 0, 0},
          width: {track.width || 0, 0},
          layer: 0,
          matrix_value_A: {1, 0},
          matrix_value_B: {0, 0},
          matrix_value_C: {0, 0},
          matrix_value_D: {1, 0},
          matrix_value_U: {0, 0},
          matrix_value_V: {0, 0},
          matrix_value_W: {1, 0},
          matrix_value_X: {0, 0},
          matrix_value_Y: {0, 0},
          modification_time: 0,
          track_id: track.id,
          version: 0,
          volume: if(is_audio(track), do: {1, 0}, else: {0, 0})
        }
      }
    ]
  end

  defp media_handler_header(track) do
    [
      mdhd: %{
        children: [],
        fields: %{
          creation_time: 0,
          duration: track.duration,
          flags: 0,
          language: 21_956,
          modification_time: 0,
          timescale: track.timescale,
          version: 0
        }
      }
    ]
  end

  defp handler(track) when is_audio(track) do
    [
      hdlr: %{
        children: [],
        fields: %{
          flags: 0,
          handler_type: "soun",
          name: "SoundHandler",
          version: 0
        }
      }
    ]
  end

  defp handler(_track) do
    [
      hdlr: %{
        children: [],
        fields: %{
          flags: 0,
          handler_type: "vide",
          name: "VideoHandler",
          version: 0
        }
      }
    ]
  end

  defp media_header(track) when is_audio(track) do
    [
      smhd: %{
        children: [],
        fields: %{
          balance: {0, 0},
          flags: 0,
          version: 0
        }
      }
    ]
  end

  defp media_header(_track) do
    [
      vmhd: %{
        children: [],
        fields: %{
          flags: 1,
          graphics_mode: 0,
          opcolor: 0,
          version: 0
        }
      }
    ]
  end

  @spec unpack(%{children: Container.t(), fields: map}) :: Track.t()
  def unpack(%{children: boxes}) do
    header = boxes[:tkhd].fields
    media = boxes[:mdia].children

    sample_table = SampleTable.unpack(media[:minf].children[:stbl])

    %Track{id: header.track_id, sample_table: sample_table}
    |> get_track_type(media)
    |> get_duration(media)
    |> get_media(media)
    |> get_sample_count(media)
  end

  defp get_track_type(track, mdia) do
    type =
      case Container.get_box_value(mdia, [:hdlr, :handler_type]) do
        "soun" -> :audio
        "vide" -> :video
        _other -> :unknown
      end

    %{track | type: type}
  end

  defp get_duration(track, mdia) do
    %{
      track
      | duration: Container.get_box_value(mdia, [:mdhd, :duration]),
        timescale: Container.get_box_value(mdia, [:mdhd, :timescale])
    }
  end

  defp get_media(track, mdia) do
    stsd = Container.get_box(mdia, [:minf, :stbl, :stsd])
    track = %{track | media_tag: Keyword.keys(stsd[:children]) |> List.first()}

    cond do
      hevc = stsd[:children][:hvc1] || stsd[:children][:hev1] ->
        %{
          track
          | media: :h265,
            width: hevc[:fields][:width],
            height: hevc[:fields][:height],
            priv_data: parse_priv_data(:h265, get_in(hevc, [:children, :hvcC, :content]))
        }

      avc = stsd[:children][:avc1] || stsd[:children][:avc3] ->
        %{
          track
          | media: :h264,
            width: avc[:fields][:width],
            height: avc[:fields][:height],
            priv_data: parse_priv_data(:h264, get_in(avc, [:children, :avcC, :content]))
        }

      mp4a = stsd[:children][:mp4a] ->
        %{
          track
          | media: :aac,
            priv_data:
              parse_priv_data(
                :aac,
                get_in(mp4a, [:children, :esds, :fields, :elementary_stream_descriptor])
              ),
            channels: mp4a[:fields][:channel_count],
            sample_rate: elem(mp4a[:fields][:sample_rate], 0)
        }

      true ->
        %{track | media: :unknown}
    end
  end

  defp get_sample_count(track, mdia) do
    %{
      track
      | sample_count: Container.get_box_value(mdia, [:minf, :stbl, :stsz, :sample_count])
    }
  end

  defp parse_priv_data(:h264, priv_data), do: ExMP4.Codec.Avc.parse(priv_data)
  defp parse_priv_data(:h265, priv_data), do: ExMP4.Codec.Hevc.parse(priv_data)
  defp parse_priv_data(_codec, priv_data), do: priv_data
end
