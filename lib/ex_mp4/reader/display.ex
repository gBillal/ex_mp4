if Application.ensure_loaded(TableRex) do
  defmodule ExMP4.Reader.Display do
    @moduledoc """
    Show information about MP4 files and tracks using [TableRex](https://hex.pm/packages/table_rex).

    To use this module, you need to add `table_rex` to your dependencies.

    To show basic information about the whole movie

        ExMP4.Reader.Display.movie_info(reader) |> IO.puts()

        +--------------------------------------------------------+
        |                       Movie Info                       |
        +===========================+============================+
        | Duration / Timescale      | 2759320/1000 (0:45:59.320) |
        | Brands (major/compatible) | mp42,isom,mp42             |
        | Progressive               | true                       |
        | Fragmented                | false                      |
        | Creation Date             | 1904-01-01 00:00:00Z       |
        | Modification Date         | 1904-01-01 00:00:00Z       |
        +---------------------------+----------------------------+

    Or to show a description of the tracks

        ExMP4.Reader.Display.tracks_info(reader) |> IO.puts()

        +-------------------------------------------------------------------------------------------------------------------------------------------------------------+
        |                                                                     Video track(s) info                                                                     |
        +====+=======================+========================+===========+===================+================+=======+=======+========+=============+===============+
        | ID | Presentation Duration | Duration               | Timescale | Number of Samples | Bitrate (kbps) | Codec | Width | Height | Sample Rate | Channel Count |
        +----+-----------------------+------------------------+-----------+-------------------+----------------+-------+-------+--------+-------------+---------------+
        | 1  | 2759320 - 0:45:59.320 | 35319296 - 0:45:59.320 | 12800     | 68983             | 1684           | H264  | 1920  | 816    |             |               |
        +----+-----------------------+------------------------+-----------+-------------------+----------------+-------+-------+--------+-------------+---------------+
        +--------------------------------------------------------------------------------------------------------------------------------------------------------------+
        |                                                                     Audio track(s) info                                                                      |
        +====+=======================+=========================+===========+===================+================+=======+=======+========+=============+===============+
        | ID | Presentation Duration | Duration                | Timescale | Number of Samples | Bitrate (kbps) | Codec | Width | Height | Sample Rate | Channel Count |
        +----+-----------------------+-------------------------+-----------+-------------------+----------------+-------+-------+--------+-------------+---------------+
        | 2  | 2759320 - 0:45:59.320 | 121686016 - 0:45:59.320 | 44100     | 118834            | 128            | AAC   |       |        | 44100       | 2             |
        +----+-----------------------+-------------------------+-----------+-------------------+----------------+-------+-------+--------+-------------+---------------+

    """

    import ExMP4.Helper, only: [timescalify: 3, format_duration: 1]

    alias ExMP4.Reader

    @type samples_options() :: [limit: non_neg_integer(), offset: non_neg_integer()]

    @doc """
    Display information about the whole movie.
    """
    @spec movie_info(Reader.t()) :: String.t()
    def movie_info(%Reader{} = reader) do
      title = "Movie Info"
      brands = Enum.join([reader.major_brand | reader.compatible_brands], ",")
      duration_ms = timescalify(reader.duration, reader.timescale, :millisecond)

      rows = [
        [
          "Duration / Timescale",
          "#{reader.duration}/#{reader.timescale} (#{format_duration(duration_ms)})"
        ],
        ["Brands (major/compatible)", brands],
        ["Progressive", reader.progressive?],
        ["Fragmented", reader.fragmented?],
        ["Creation Date", reader.creation_time],
        ["Modification Date", reader.modification_time]
      ]

      rows
      |> TableRex.Table.new([], title)
      |> TableRex.Table.render!(title_separator_symbol: "=")
    end

    @doc """
    Display tracks information.
    """
    @spec tracks_info(Reader.t()) :: String.t()
    def tracks_info(%Reader{} = reader) do
      Reader.tracks(reader)
      |> Enum.reduce(%{}, fn track, tracks ->
        Map.update(tracks, track.type, [track], &(&1 ++ [track]))
      end)
      |> Enum.map_join(&track_info(reader, elem(&1, 0), elem(&1, 1)))
    end

    @doc """
    Display samples from a track.
    """
    @spec samples(Reader.t(), ExMP4.Track.id(), Keyword.t()) :: String.t()
    def samples(%Reader{} = reader, track_id, opts \\ []) do
      track = Reader.track(reader, track_id)
      title = "Sample Table"
      headers = ["number", "dts", "cts", "offset", "size", "sync?"]

      offset = Keyword.get(opts, :offset, 0)

      rows =
        reader
        |> Reader.stream(tracks: track_id)
        |> Stream.drop(offset)
        |> Stream.take(opts[:limit] || 10)
        |> Stream.with_index(offset)
        |> Enum.map(fn {sample, num} ->
          dts_ms = timescalify(sample.dts, track.timescale, :millisecond)
          pts_ms = timescalify(sample.pts, track.timescale, :millisecond)

          [
            num,
            "#{sample.dts} - #{format_duration(dts_ms)}",
            "#{sample.pts} - #{format_duration(pts_ms)}",
            sample.offset,
            sample.size,
            sample.sync?
          ]
        end)

      rows
      |> TableRex.Table.new(headers, title)
      |> TableRex.Table.render!(title_separator_symbol: "=")
    end

    defp track_info(reader, type, tracks) do
      title = "#{String.capitalize(to_string(type))} track(s) info"
      movie_duration_ms = Reader.duration(reader, :millisecond)

      headers = [
        "ID",
        "Presentation Duration",
        "Duration",
        "Timescale",
        "Number of Samples",
        "Bitrate (kbps)",
        "Codec",
        "Width",
        "Height",
        "Sample Rate",
        "Channel Count"
      ]

      rows =
        Enum.map(tracks, fn track ->
          track_duration_ms = ExMP4.Track.duration(track, :millisecond)

          [
            track.id,
            "#{reader.duration} - #{format_duration(movie_duration_ms)}",
            "#{track.duration} - #{format_duration(track_duration_ms)}",
            track.timescale,
            track.sample_count,
            div(ExMP4.Track.bitrate(track), 1000),
            track.media |> to_string() |> String.upcase(),
            track.width,
            track.height,
            track.sample_rate,
            track.channels
          ]
        end)

      rows
      |> TableRex.Table.new(headers, title)
      |> TableRex.Table.render!(title_separator_symbol: "=")
    end
  end
end
