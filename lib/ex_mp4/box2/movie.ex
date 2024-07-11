defmodule ExMP4.Box.Movie do
  @moduledoc """
  A module providing a function assembling an MPEG-4 movie box.

  The movie box (`moov`) is a top-level box that contains information about
  a presentation as a whole. It consists of:

    * exactly one movie header (`mvhd` atom)

      The movie header contains media-independent data, such as the
      number of tracks, volume, duration or timescale (presentation-wide).

    * one or more track box (`trak` atom)

    * zero or one movie extends box (`mvex` atom)
  """
  alias ExMP4.Box.Track, as: TrackBox
  alias ExMP4.{Container, Track, Track.FragmentedSampleTable}

  @type movie_header :: %{
          :duration => integer(),
          :timescale => integer(),
          :creation_time => DateTime.t(),
          :modification_time => DateTime.t(),
          :fragmented? => boolean()
        }

  @doc """
  Assembles a list of tracks into a `moov` box.
  """
  @spec assemble([Track.t()], Keyword.t()) :: Container.t()
  @spec assemble([Track.t()], Keyword.t(), Container.t()) :: Container.t()
  def assemble(tracks, header_opts, extensions \\ []) do
    tracks = Enum.map(tracks, &Track.finalize(&1, ExMP4.movie_timescale()))

    header = movie_header(tracks, header_opts)
    track_boxes = Enum.flat_map(tracks, &TrackBox.assemble/1)

    [moov: %{children: header ++ track_boxes ++ extensions, fields: %{}}]
  end

  @doc """
  Deserializes and unpacks a `moov` box data.

  The return type is a tuple with the first element as the movie header and the
  second element as a list of tracks.
  """
  @spec unpack(Container.t()) :: {movie_header(), [Track.t()]}
  def unpack(box) do
    mvhd = Container.get_box(box, [:moov, :mvhd])

    movie_header = %{
      duration: mvhd[:fields][:duration],
      timescale: mvhd[:fields][:timescale],
      creation_time: DateTime.add(ExMP4.base_date(), mvhd[:fields][:creation_time]),
      modification_time: DateTime.add(ExMP4.base_date(), mvhd[:fields][:modification_time]),
      fragmented?: get_in(box, [:moov, :children, :mvex]) != nil
    }

    tracks =
      box[:moov][:children]
      |> Keyword.get_values(:trak)
      |> Enum.map(&TrackBox.unpack/1)
      |> Map.new(&{&1.id, &1})

    tracks =
      if movie_header.fragmented? do
        get_in(box, [:moov, :children, :mvex, :children])
        |> Keyword.get_values(:trex)
        |> Enum.map(&unpack_trex(tracks[&1.fields.track_id], &1))
        |> Map.new(&{&1.id, &1})
      else
        tracks
      end

    {movie_header, Map.values(tracks)}
  end

  @doc false
  @spec adjust_chunk_offsets(Container.t()) :: Container.t()
  def adjust_chunk_offsets(movie_box) do
    movie_box_size = movie_box |> Container.serialize!() |> IO.iodata_length()
    movie_box_children = get_in(movie_box, [:moov, :children])

    # updates all `trak` boxes by adding `movie_box_size` to the offset of each chunk in their sample tables
    track_boxes_with_offset =
      movie_box_children
      |> Keyword.get_values(:trak)
      |> Enum.map(fn trak ->
        Container.update_box(
          trak.children,
          [:mdia, :minf, :stbl, :stco],
          [:fields, :entry_list],
          &Enum.map(&1, fn %{chunk_offset: offset} -> %{chunk_offset: offset + movie_box_size} end)
        )
      end)
      |> Enum.map(&{:trak, %{children: &1, fields: %{}}})

    # replaces all `trak` boxes with the ones with updated chunk offsets
    movie_box_children
    |> Keyword.delete(:trak)
    |> Keyword.merge(track_boxes_with_offset)
    |> then(&[moov: %{children: &1, fields: %{}}])
  end

  @doc false
  @spec update_fragment_duration(Container.t(), integer()) :: Container.t()
  def update_fragment_duration(movie_box, duration) do
    Container.update_box(movie_box, [:moov, :mvex, :mehd], [:fields], fn fields ->
      %{fields | fragment_duration: duration}
    end)
  end

  defp movie_header(tracks, opts) do
    longest_track = Enum.max_by(tracks, & &1.movie_duration)

    [
      mvhd: %{
        children: [],
        fields: %{
          creation_time: DateTime.diff(opts[:creation_time], ExMP4.base_date()),
          duration: longest_track.movie_duration,
          flags: 0,
          matrix_value_A: {1, 0},
          matrix_value_B: {0, 0},
          matrix_value_C: {0, 0},
          matrix_value_D: {1, 0},
          matrix_value_U: {0, 0},
          matrix_value_V: {0, 0},
          matrix_value_W: {1, 0},
          matrix_value_X: {0, 0},
          matrix_value_Y: {0, 0},
          modification_time: DateTime.diff(opts[:modification_time], ExMP4.base_date()),
          next_track_id: length(tracks) + 1,
          quicktime_current_time: 0,
          quicktime_poster_time: 0,
          quicktime_preview_duration: 0,
          quicktime_preview_time: 0,
          quicktime_selection_duration: 0,
          quicktime_selection_time: 0,
          rate: {1, 0},
          timescale: ExMP4.movie_timescale(),
          version: 0,
          volume: {1, 0}
        }
      }
    ]
  end

  defp unpack_trex(track, %{fields: fields}) do
    %{
      track
      | frag_sample_table: %FragmentedSampleTable{
          default_sample_description_id: fields.default_sample_duration,
          default_sample_duration: fields.default_sample_duration,
          default_sample_flags: fields.default_sample_flags,
          default_sample_size: fields.default_sample_size
        }
    }
  end
end
