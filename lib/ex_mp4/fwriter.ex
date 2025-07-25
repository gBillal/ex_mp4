defmodule ExMP4.FWriter do
  @moduledoc """
  Module responsible for writing fragmented MP4.
  """

  alias ExMP4.{Box, Track}

  @mdat_header_size 8

  @type t :: %__MODULE__{
          writer_mod: module(),
          writer_state: term(),
          tracks: %{integer() => Track.t()},
          current_fragments: %{integer() => {Box.Traf.t(), [iodata()]}},
          current_segments: %{integer() => Box.Sidx.t()},
          sequence_number: integer(),
          base_data_offset: integer(),
          ftyp_box_size: integer(),
          movie_box: Box.Moov.t() | nil,
          moof_base_offset: boolean()
        }

  @typedoc """
  Options to supply when creating the writer.
  """
  @type new_opts :: [
          major_brand: binary(),
          compatible_brands: [binary()],
          minor_version: integer(),
          creation_time: DateTime.t(),
          modification_time: DateTime.t(),
          duration: integer() | boolean(),
          moof_base_offset: boolean()
        ]

  @type writer_options :: any()

  defstruct writer_mod: nil,
            writer_state: nil,
            tracks: %{},
            current_fragments: %{},
            current_segments: %{},
            sequence_number: 0,
            base_data_offset: 0,
            ftyp_box_size: 0,
            movie_box: nil,
            moof_base_offset: false

  @doc """
  Create a new fragmented mp4 writer.

  The tracks are assigned an id starting from 1.

  The following options can be provided:
    * `major_brand` - Set the major brand
    * `compatible_brands` - Set the compatible brands
    * `creation_time` - Set the creation time
    * `modification_time` - Set the modification time
    * `duration` - Set the total duration if known. The value can be `true`, `false` or an integer.

      If `true`, the total duration of the presentation is calculated when closing the `writer` and the `mehd` box is
      set to include the fragment duration. Note that this needs the output target to support seeking (not suitable for live streaming.)

      If `false`, the total duration is not calculated and the `mehd` box is not included. This is suitable for real time or
      for presentations where the total duration is not available.

      If an integer, it's the total duration in the `movie` timescale and it'll be set in the `mehd` box.
    * `moof_base_offset` - if `true`, it indicates that the `base‐data‐offset` for the track fragments
      is the position of the first byte of the enclosing Movie Fragment Box. Defaults to: `false`.

  The last argument is an optional module implementing `ExMP4.FragDataWriter`.
  """
  @spec new(writer_options(), [ExMP4.Track.t()], new_opts(), module()) ::
          {:ok, t()} | {:error, term()}
  def new(writer_opts, tracks, opts \\ [], module \\ ExMP4.FragDataWriter.File) do
    do_new_writer(writer_opts, module, tracks, opts)
  end

  @doc """
  The same as `new/2`, but raises if it fails.
  """
  @spec new!(writer_options(), [ExMP4.Track.t()], new_opts(), module()) :: t()
  def new!(writer_opts, tracks, opts \\ [], module \\ ExMP4.FragDataWriter.File) do
    case new(writer_opts, tracks, opts, module) do
      {:ok, writer} -> writer
      {:error, reason} -> raise "cannot open writer: #{inspect(reason)}"
    end
  end

  @doc """
  Get a track by id or type.
  """
  @spec track(t(), integer() | atom()) :: Track.t() | nil
  def track(writer, id_or_type) when is_atom(id_or_type) do
    Map.values(writer.tracks) |> Enum.find(&(&1.type == id_or_type))
  end

  def track(writer, id_or_type) when is_integer(id_or_type) do
    Map.get(writer.tracks, id_or_type)
  end

  @doc """
  Creates a new media segment.

  Calling this function is optional. If not called, no Segment Index Box (`sidx`) will be  added.

  > ### Segments and Fragments {: .info}
  >
  > Current implementation restricts each segment to contain exactly one fragment.
  > This is why there is no separate `flush_segment` function - the segment is automatically `closed`
  > when the single fragment is completed.
  """
  @spec create_segment(t()) :: t()
  def create_segment(%{current_segments: segments}) when map_size(segments) != 0 do
    raise "Hierarchical segments are not supported"
  end

  def create_segment(%{tracks: tracks} = writer) do
    segments =
      Map.new(tracks, fn {track_id, track} ->
        sidx = %Box.Sidx{
          reference_id: track_id,
          timescale: track.timescale,
          earliest_presentation_time: track.duration,
          first_offset: 0,
          entries: []
        }

        {track_id, sidx}
      end)

    %{writer | current_segments: segments}
  end

  @doc """
  Create a new empty fragment.

  After adding samples, the fragment should be finalized, with `flush_fragment/1`.
  """
  @spec create_fragment(t()) :: t()
  def create_fragment(%{tracks: tracks} = writer) do
    track_ids = Map.keys(tracks)

    fragments =
      Map.new(track_ids, fn track_id ->
        traf = %Box.Traf{
          tfhd: %Box.Tfhd{track_id: track_id},
          tfdt: %Box.Tfdt{base_media_decode_time: tracks[track_id].duration},
          trun: [%Box.Trun{}]
        }

        {track_id, {traf, []}}
      end)

    %{
      writer
      | current_fragments: fragments,
        sequence_number: writer.sequence_number + 1
    }
  end

  @doc """
  Write a sample to the current fragment.
  """
  @spec write_sample(t(), ExMP4.Sample.t()) :: t()
  def write_sample(%{current_fragments: fragments} = writer, sample) do
    fragments =
      Map.update!(fragments, sample.track_id, fn {traf, data} ->
        {Box.Traf.store_sample(traf, sample), [sample.payload | data]}
      end)

    %{writer | current_fragments: fragments}
  end

  @doc """
  Finalizes the current fragment and segment (if any).
  """
  @spec flush_fragment(t()) :: t()
  def flush_fragment(%{tracks: tracks, moof_base_offset: moof_base_offset} = writer) do
    {moof, mdat} = build_moof_and_mdat(writer)
    {segments, segments_size} = finalize_segments(writer.current_segments, moof, mdat)

    referenced_size = Box.size(moof) + Box.size(mdat)

    base_data_offset =
      writer.base_data_offset + Box.size(moof) + @mdat_header_size +
        if moof_base_offset, do: 0, else: segments_size

    moof = Box.Moof.update_base_offsets(moof, base_data_offset, moof_base_offset)

    tracks =
      Enum.reduce(moof.traf, tracks, fn traf, tracks ->
        Map.update!(
          tracks,
          traf.tfhd.track_id,
          &%{&1 | duration: &1.duration + Box.Traf.duration(traf)}
        )
      end)

    writer_state =
      writer.writer_mod.write_segment(writer.writer_state, List.flatten(segments, [moof, mdat]))

    base_data_offset =
      if moof_base_offset,
        do: 0,
        else: writer.base_data_offset + segments_size + referenced_size

    %{
      writer
      | tracks: tracks,
        writer_state: writer_state,
        current_fragments: %{},
        current_segments: %{},
        base_data_offset: base_data_offset
    }
  end

  @doc """
  Close the writer.
  """
  @spec close(t()) :: :ok
  def close(writer) do
    writer = update_fragment_duration(writer)
    writer.writer_mod.close(writer.writer_state)
  end

  defp do_new_writer(input, writer_mod, tracks, opts) do
    with {:ok, writer_state} <- writer_mod.open(input) do
      opts = validate_new_opts(opts)

      tracks =
        tracks
        |> Enum.with_index(1)
        |> Enum.map(fn {track, id} -> new_track(id, track) end)
        |> Map.new(&{&1.id, &1})

      writer =
        %__MODULE__{
          writer_mod: writer_mod,
          writer_state: writer_state,
          tracks: tracks,
          moof_base_offset: opts[:moof_base_offset]
        }

      {:ok, write_init_header(writer, opts)}
    end
  end

  defp validate_new_opts(opts) do
    utc_date = DateTime.utc_now()

    moof_base_offset = Keyword.get(opts, :moof_base_offset, false)
    {major_brand, compatible_brands} = brands(moof_base_offset)

    Keyword.validate!(opts,
      major_brand: major_brand,
      minor_version: 512,
      compatible_brands: compatible_brands,
      creation_time: utc_date,
      modification_time: utc_date,
      duration: false,
      moof_base_offset: false,
      sidx: false
    )
  end

  defp write_init_header(writer, opts) do
    tracks = Map.values(writer.tracks)
    fragment_duration = fragment_duration(opts[:duration])

    ftyp_box = %Box.Ftyp{
      major_brand: opts[:major_brand],
      minor_version: opts[:minor_version],
      compatible_brands: opts[:compatible_brands]
    }

    mehd_box =
      if fragment_duration,
        do: %Box.Mehd{fragment_duration: fragment_duration},
        else: nil

    movie_box = %Box.Moov{
      mvhd: %Box.Mvhd{
        creation_time: opts[:creation_time],
        modification_time: opts[:modification_time],
        next_track_id: length(tracks) + 1
      },
      trak: Enum.map(tracks, &Track.to_trak(&1, ExMP4.movie_timescale())),
      mvex: %Box.Mvex{
        mehd: mehd_box,
        trex: Enum.map(tracks, & &1.trex)
      }
    }

    writer_state = writer.writer_mod.write_init_header(writer.writer_state, [ftyp_box, movie_box])

    base_data_offset =
      case writer.moof_base_offset do
        true -> 0
        false -> Box.size(ftyp_box) + Box.size(movie_box)
      end

    %{
      writer
      | writer_state: writer_state,
        base_data_offset: base_data_offset,
        ftyp_box_size: Box.size(ftyp_box),
        movie_box: if(fragment_duration == 0, do: movie_box)
    }
  end

  defp new_track(track_id, track) do
    %{
      track
      | id: track_id,
        duration: 0,
        sample_count: 0,
        sample_table: %Box.Stbl{stsz: %Box.Stsz{}, stco: %Box.Stco{}},
        trex: %Box.Trex{
          track_id: track_id,
          default_sample_flags: if(track.type == :video, do: 0x10000, else: 0)
        },
        trafs: []
    }
  end

  defp build_moof_and_mdat(writer) do
    moof = %Box.Moof{mfhd: %Box.Mfhd{sequence_number: writer.sequence_number}}
    mdat = %Box.Mdat{content: []}

    {moof, mdat} =
      Enum.reduce(writer.current_fragments, {moof, mdat}, fn {_track_id, {traf, data}},
                                                             {moof, mdat} ->
        traf = Box.Traf.finalize(traf, writer.moof_base_offset)
        data = Enum.reverse(data)

        moof = %Box.Moof{moof | traf: [traf | moof.traf]}
        mdat = %Box.Mdat{mdat | content: [data | mdat.content]}

        {moof, mdat}
      end)

    moof = %Box.Moof{moof | traf: Enum.reverse(moof.traf)}
    mdat = %Box.Mdat{mdat | content: Enum.reverse(mdat.content)}

    {moof, mdat}
  end

  defp finalize_segments(segments, _moof, _mdat) when map_size(segments) == 0, do: {[], 0}

  defp finalize_segments(segments, moof, mdat) do
    Enum.map_reduce(moof.traf, 0, fn traf, acc ->
      segment = segments[traf.tfhd.track_id]

      segment = %Box.Sidx{
        segment
        | first_offset: acc,
          entries: [
            %{
              reference_type: 0,
              referenced_size: Box.size(moof) + Box.size(mdat),
              subsegment_duration: Box.Traf.duration(traf),
              starts_with_sap: 1,
              sap_type: 0,
              sap_delta_time: 0
            }
          ]
      }

      {segment, acc + Box.size(segment)}
    end)
    |> then(fn {segments, size} -> {Enum.reverse(segments), size} end)
  end

  defp update_fragment_duration(%{movie_box: nil} = writer), do: writer

  defp update_fragment_duration(%{movie_box: moov_box} = writer) do
    fragment_duration =
      writer.tracks
      |> Map.values()
      |> Enum.map(&ExMP4.Helper.timescalify(&1.duration, &1.timescale, ExMP4.movie_timescale()))
      |> Enum.max()

    mvex = moov_box.mvex
    mvex = %{mvex | mehd: %{mvex.mehd | fragment_duration: fragment_duration}}

    writer_state =
      writer.writer_mod.write(
        writer.writer_state,
        Box.serialize(%{moov_box | mvex: mvex}),
        {:bof, writer.ftyp_box_size}
      )

    %{writer | writer_state: writer_state}
  end

  defp fragment_duration(false), do: nil
  defp fragment_duration(true), do: 0
  defp fragment_duration(duration) when is_integer(duration), do: duration

  defp brands(true), do: {"iso5", ["iso6", "mp41"]}
  defp brands(_moof_base_offset), do: {"mp42", ["mp42", "mp41", "isom", "avc1"]}
end
