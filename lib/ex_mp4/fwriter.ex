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
          current_fragments: %{integer() => Box.Traf.t()},
          fragments_data: %{integer() => [binary()]},
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

  defstruct writer_mod: nil,
            writer_state: nil,
            tracks: %{},
            current_fragments: %{},
            fragments_data: %{},
            sequence_number: 0,
            base_data_offset: 0,
            ftyp_box_size: 0,
            movie_box: nil,
            moof_base_offset: false

  @doc """
  Create a new mp4 writer that writes to filesystem.

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
  @spec new(Path.t(), [ExMP4.Track.t()], new_opts(), module()) :: {:ok, t()} | {:error, term()}
  def new(filename, tracks, opts \\ [], module \\ ExMP4.FragDataWriter.File) do
    do_new_writer(filename, module, tracks, opts)
  end

  @doc """
  The same as `new/2`, but raises if it fails.
  """
  @spec new!(Path.t(), [ExMP4.Track.t()], new_opts(), module()) :: t()
  def new!(filepath, tracks, opts \\ [], module \\ ExMP4.FragDataWriter.File) do
    case new(filepath, tracks, opts, module) do
      {:ok, writer} -> writer
      {:error, reason} -> raise "could not open writer: #{inspect(reason)}"
    end
  end

  @doc """
  Create a new empty fragment.

  After adding samples, the fragment should be flashed, with `flush_fragment/1`.
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

        {track_id, traf}
      end)

    data = Enum.reduce(track_ids, writer.fragments_data, &Map.put(&2, &1, []))

    %{
      writer
      | current_fragments: fragments,
        fragments_data: data,
        sequence_number: writer.sequence_number + 1
    }
  end

  @doc """
  Write a sample to the current fragment.
  """
  @spec write_sample(t(), ExMP4.Sample.t()) :: t()
  def write_sample(%{current_fragments: fragments} = writer, sample) do
    fragments = Map.update!(fragments, sample.track_id, &Box.Traf.store_sample(&1, sample))
    fragments_data = Map.update!(writer.fragments_data, sample.track_id, &[sample.payload | &1])

    %{writer | current_fragments: fragments, fragments_data: fragments_data}
  end

  @doc """
  Flush the current fragment.
  """
  @spec flush_fragment(t()) :: t()
  def flush_fragment(%{tracks: tracks, moof_base_offset: moof_base_offset} = writer) do
    track_ids = Map.keys(tracks) |> Enum.sort()

    fragments =
      Map.new(writer.current_fragments, fn {track_id, traf} ->
        {track_id, Box.Traf.finalize(traf, moof_base_offset)}
      end)

    moof = %Box.Moof{
      mfhd: %Box.Mfhd{sequence_number: writer.sequence_number},
      traf: Enum.map(track_ids, &fragments[&1])
    }

    base_data_offset = writer.base_data_offset + Box.size(moof) + @mdat_header_size
    moof = Box.Moof.update_base_offsets(moof, base_data_offset, moof_base_offset)
    mdat = %Box.Mdat{content: Enum.map(track_ids, &Enum.reverse(writer.fragments_data[&1]))}

    tracks =
      Enum.reduce(moof.traf, tracks, fn traf, tracks ->
        Map.update!(
          tracks,
          traf.tfhd.track_id,
          &%{&1 | duration: &1.duration + Box.Traf.duration(traf)}
        )
      end)

    writer.writer_mod.write_fragment(writer.writer_state, [
      Box.serialize(moof),
      Box.serialize(mdat)
    ])

    base_data_offset =
      if moof_base_offset, do: 0, else: writer.base_data_offset + Box.size(moof) + Box.size(mdat)

    %{
      writer
      | tracks: tracks,
        current_fragments: %{},
        fragments_data: %{},
        base_data_offset: base_data_offset
    }
  end

  @doc """
  Close the writer.
  """
  @spec close(t()) :: :ok
  def close(writer) do
    update_fragment_duration(writer)
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
      moof_base_offset: false
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

    writer.writer_mod.write_init_header(writer.writer_state, [
      Box.serialize(ftyp_box),
      Box.serialize(movie_box)
    ])

    base_data_offset =
      case writer.moof_base_offset do
        true -> 0
        false -> Box.size(ftyp_box) + Box.size(movie_box)
      end

    %{
      writer
      | base_data_offset: base_data_offset,
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
        sample_table: %Box.Stbl{stsz: %Box.Stsz{}},
        trex: %Box.Trex{
          track_id: track_id,
          default_sample_flags: if(track.type == :video, do: 0x10000, else: 0)
        },
        trafs: []
    }
  end

  defp update_fragment_duration(%{movie_box: nil}), do: :ok

  defp update_fragment_duration(%{movie_box: moov_box} = writer) do
    fragment_duration =
      writer.tracks
      |> Map.values()
      |> Enum.map(&ExMP4.Helper.timescalify(&1.duration, &1.timescale, ExMP4.movie_timescale()))
      |> Enum.max()

    mvex = moov_box.mvex
    mvex = %{mvex | mehd: %{mvex.mehd | fragment_duration: fragment_duration}}

    writer.writer_mod.write(
      writer.writer_state,
      Box.serialize(%{moov_box | mvex: mvex}),
      {:bof, writer.ftyp_box_size}
    )
  end

  defp fragment_duration(false), do: nil
  defp fragment_duration(true), do: 0
  defp fragment_duration(duration) when is_integer(duration), do: duration

  defp brands(true), do: {"iso5", ["iso5", "iso6"]}
  defp brands(_moof_base_offset), do: {"mp42", ["mp42", "mp41", "isom", "avc1"]}
end
