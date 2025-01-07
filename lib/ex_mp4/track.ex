defmodule ExMP4.Track do
  @moduledoc """
  A struct describing an MP4 track.
  """

  alias ExMP4.Box.{Stbl, Traf, Trak, Trex}
  alias ExMP4.{Helper, Sample}

  @type id :: non_neg_integer()
  @type codecs :: :h264 | :h265 | :vp8 | :vp9 | :aac | :opus | :raw | :unknown
  @type media_types :: :video | :audio | :subtitle | :unknown

  @public_fields ~w(id type media media_tag width height sample_rate channels priv_data timescale duration sample_count)a

  @typedoc """
  Struct describing an mp4 track.

  The public fields are:
    * `:id` - the track id
    * `:type` - the type of the media of the track
    * `:media` - the codec used to encode the media.
    * `:media_tag` - the box `name` to use for the `:media`.

        This field is used to indicate the layout of some codec specific data, take for example `H264`,
        `avc1` indicates that parameter sets are included in the sample description and removed from
        the samples themselves.
    * `:priv_data` - private data specific to the contained `:media`.
    * `:duration` - the duration of the track in `:timescale` units.
    * `:timescale` - the timescale used for the track.
    * `:width` - the width of the video frames.
    * `:height` - the height of the video frames.
    * `:sample_rate` - the sample rate of audio samples.
    * `:channels` - the number of audio channels.
    * `:sample_count` - the total count of samples.
  """
  @type t :: %__MODULE__{
          id: id(),
          type: media_types(),
          media: codecs(),
          media_tag: atom(),
          priv_data: binary() | struct(),
          duration: non_neg_integer(),
          timescale: non_neg_integer(),
          width: non_neg_integer() | nil,
          height: non_neg_integer() | nil,
          sample_rate: non_neg_integer() | nil,
          channels: non_neg_integer() | nil,
          sample_count: non_neg_integer(),
          sample_table: Stbl.t() | nil,
          trafs: [Traf.t()],
          trex: Trex.t() | nil
        }

  @derive {Inspect, only: @public_fields}
  defstruct [
    :id,
    :type,
    :media,
    :media_tag,
    :width,
    :height,
    :sample_rate,
    :channels,
    :sample_table,
    :movie_duration,
    :trex,
    priv_data: <<>>,
    trafs: [],
    timescale: 1000,
    duration: 0,
    sample_count: 0,
    _iter_index: 1,
    _iter_duration: 0,
    _chunk_id: 1,
    _stsc_entry: %{first_chunk: 1, samples_per_chunk: 0, sample_description_index: 1}
  ]

  @doc false
  def updatable_fields(),
    do: ~w(type media media_tag width height sample_rate channels priv_data)a

  @spec from_trak(Trak.t()) :: t()
  def from_trak(%Trak{} = trak) do
    stbl = trak.mdia.minf.stbl

    %__MODULE__{id: trak.tkhd.track_id, sample_table: stbl}
    |> get_track_type(trak)
    |> get_duration(trak)
    |> get_media(stbl.stsd)
    |> get_sample_count(stbl)
  end

  @spec to_trak(t(), ExMP4.timescale()) :: Trak.t()
  def to_trak(%{sample_table: stbl} = track, movie_timescale) do
    %Trak{
      tkhd: %ExMP4.Box.Tkhd{
        track_id: track.id,
        duration: Helper.timescalify(track.duration, track.timescale, movie_timescale),
        volume: if(track.type == :audio, do: 0x0100, else: 0),
        width: {track.width || 0, 0},
        height: {track.height || 0, 0}
      },
      mdia: %ExMP4.Box.Mdia{
        mdhd: %ExMP4.Box.Mdhd{
          duration: track.duration,
          timescale: track.timescale
        },
        hdlr: trak_media_handler(track),
        minf: %ExMP4.Box.Minf{
          vmhd: trak_video_header(track),
          smhd: trak_audio_header(track),
          stbl: %ExMP4.Box.Stbl{
            stbl
            | stsd: sample_description_table(track),
              stts: reverse_entries(stbl.stts),
              ctts: reverse_entries(stbl.ctts),
              stss: reverse_entries(stbl.stss),
              stsz: reverse_entries(stbl.stsz),
              stz2: reverse_entries(stbl.stz2),
              stsc: reverse_entries(stbl.stsc),
              stco: reverse_entries(stbl.stco),
              co64: reverse_entries(stbl.co64)
          }
        }
      }
    }
  end

  @doc """
  Create a new track
  """
  @spec new(Keyword.t()) :: t()
  def new(opts), do: struct!(__MODULE__, opts)

  @doc """
  Get the duration of the track.
  """
  @spec duration(t(), Helper.timescale()) :: integer()
  @spec duration(t()) :: integer()
  def duration(track, unit_or_timescale \\ :millisecond) do
    Helper.timescalify(track.duration, track.timescale, unit_or_timescale)
  end

  @doc """
  Get the bitrate of the track in `bps` (bit per second)
  """
  @spec bitrate(t()) :: non_neg_integer()
  def bitrate(track) do
    div(total_size(track) * 1000 * 8, duration(track, :millisecond))
  end

  @doc """
  Get the fps (frames per second) of the video track.
  """
  @spec fps(t()) :: number()
  def fps(%{type: :video} = track) do
    track.sample_count * 1_000 / duration(track, :millisecond)
  end

  def fps(_track), do: 0

  @doc false
  @spec store_sample(t(), Sample.t()) :: t()
  def store_sample(%{sample_table: stbl} = track, sample) do
    stsc_entry = %{track._stsc_entry | samples_per_chunk: track._stsc_entry.samples_per_chunk + 1}
    duration = track.duration + sample.duration

    stbl
    |> update_stts(sample)
    |> update_ctts(sample, track.type)
    |> update_stsz(sample)
    |> update_stss(sample, track.type)
    |> then(&%{track | sample_table: &1, duration: duration, _stsc_entry: stsc_entry})
  end

  @doc false
  @spec flush_chunk(t(), ExMP4.offset()) :: t()
  def flush_chunk(%{sample_table: stbl} = track, chunk_offset) do
    samples_per_chunk = track._stsc_entry.samples_per_chunk
    stco = %{stbl.stco | entries: [chunk_offset | stbl.stco.entries]}

    stsc =
      case stbl.stsc.entries do
        [%{samples_per_chunk: ^samples_per_chunk} | _rest] = entries ->
          %{stbl.stsc | entries: entries}

        entries ->
          %{stbl.stsc | entries: [track._stsc_entry | entries]}
      end

    stbl = %Stbl{stbl | stsc: stsc, stco: stco}
    chunk_id = track._chunk_id + 1

    %{
      track
      | sample_table: stbl,
        _chunk_id: chunk_id,
        _stsc_entry: %{
          first_chunk: chunk_id,
          samples_per_chunk: 0,
          sample_description_index: 1
        }
    }
  end

  defp total_size(%{trex: nil, sample_table: stbl}) do
    case stbl do
      %{stsz: nil} -> Enum.sum(stbl.stz2.entries)
      %{stsz: %{sample_size: 0}} -> Enum.sum(stbl.stsz.entries)
      %{stsz: %{sample_size: size}} -> size * stbl.stsz.sample_count
    end
  end

  defp total_size(%{trafs: trafs, trex: trex}) do
    Enum.reduce(trafs, 0, &(Traf.total_size(&1, trex) + &2))
  end

  defp get_track_type(track, trak) do
    type =
      case trak.mdia.hdlr.handler_type do
        "soun" -> :audio
        "vide" -> :video
        _other -> :unknown
      end

    %{track | type: type}
  end

  defp get_duration(track, trak) do
    %{
      track
      | duration: trak.mdia.mdhd.duration,
        timescale: trak.mdia.mdhd.timescale
    }
  end

  defp get_media(track, %{hvc1: hvc1, hev1: hev1}) when not is_nil(hvc1) or not is_nil(hev1) do
    hevc = hvc1 || hev1

    %{
      track
      | media: :h265,
        width: hevc.width,
        height: hevc.height,
        priv_data: hevc.hvcC,
        media_tag: if(hvc1, do: :hvc1, else: :hev1)
    }
  end

  defp get_media(track, %{avc1: avc1, avc3: avc3}) when not is_nil(avc1) or not is_nil(avc3) do
    avc = avc1 || avc3

    %{
      track
      | media: :h264,
        width: avc.width,
        height: avc.height,
        priv_data: avc.avcC,
        media_tag: if(avc1, do: :avc1, else: :avc3)
    }
  end

  defp get_media(track, %{vp08: vp08, vp09: vp09}) when not is_nil(vp08) or not is_nil(vp09) do
    {vpx, media, media_tag} =
      case vp08 do
        nil -> {vp09, :vp9, :vp09}
        _other -> {vp08, :vp8, :vp08}
      end

    %{
      track
      | media: media,
        width: vpx.width,
        height: vpx.height,
        priv_data: vpx.vpcC,
        media_tag: media_tag
    }
  end

  defp get_media(track, %{mp4a: mp4a}) when not is_nil(mp4a) do
    %{
      track
      | media: :aac,
        priv_data: mp4a.esds,
        channels: mp4a.channel_count,
        sample_rate: elem(mp4a.sample_rate, 0),
        media_tag: :esds
    }
  end

  defp get_media(track, %{ipcm: ipcm, fpcm: fpcm}) when not is_nil(ipcm) or not is_nil(fpcm) do
    {pcm, tag} = if is_nil(fpcm), do: {ipcm, :ipcm}, else: {fpcm, :fpcm}

    %{
      track
      | media: :raw,
        priv_data: pcm.pcmC,
        channels: pcm.channel_count,
        sample_rate: elem(pcm.sample_rate, 0),
        media_tag: tag
    }
  end

  defp get_media(track, _stsd) do
    %{track | media: :unknown}
  end

  defp get_sample_count(track, stbl) do
    %{track | sample_count: stbl.stsz.sample_count}
  end

  # Samples storage
  defp update_stts(%{stts: stts} = stbl, %Sample{duration: duration}) do
    entries =
      case stts.entries do
        [%{sample_count: count, sample_delta: ^duration} = entry | entries] ->
          [%{entry | sample_count: count + 1} | entries]

        entries ->
          [%{sample_count: 1, sample_delta: duration} | entries]
      end

    %Stbl{stbl | stts: %{stts | entries: entries}}
  end

  defp update_ctts(%{ctts: ctts} = stbl, %Sample{dts: dts, pts: pts}, :video) do
    diff = pts - dts

    entries =
      case ctts.entries do
        [%{sample_count: count, sample_offset: ^diff} = entry | entries] ->
          [%{entry | sample_count: count + 1} | entries]

        entries ->
          [%{sample_count: 1, sample_offset: diff} | entries]
      end

    %Stbl{stbl | ctts: %{ctts | entries: entries}}
  end

  defp update_ctts(stbl, _sample, _other), do: stbl

  defp update_stsz(%{stsz: stsz} = stbl, %Sample{payload: payload}) do
    stsz = %{
      stsz
      | sample_count: stsz.sample_count + 1,
        entries: [byte_size(payload) | stsz.entries]
    }

    %Stbl{stbl | stsz: stsz}
  end

  defp update_stss(%{stss: stss} = stbl, %Sample{sync?: true}, :video) do
    %Stbl{stbl | stss: %{stss | entries: [stbl.stsz.sample_count | stss.entries]}}
  end

  defp update_stss(stbl, _sample, _other), do: stbl

  # Convert to trak box
  defp trak_media_handler(%{type: :audio}) do
    %ExMP4.Box.Hdlr{
      handler_type: "soun",
      name: "SoundHandler"
    }
  end

  defp trak_media_handler(%{type: :video}) do
    %ExMP4.Box.Hdlr{
      handler_type: "vide",
      name: "VideoHandler"
    }
  end

  defp trak_video_header(%{type: :video}), do: %ExMP4.Box.Vmhd{}
  defp trak_video_header(_track), do: nil

  defp trak_audio_header(%{type: :audio}), do: %ExMP4.Box.Smhd{}
  defp trak_audio_header(_track), do: nil

  defp sample_description_table(%{media: :h264} = track) do
    avc = %ExMP4.Box.Avc{
      tag: track.media_tag && to_string(track.media_tag),
      width: track.width,
      height: track.height,
      avcC: track.priv_data
    }

    case track.media_tag do
      :avc3 -> %ExMP4.Box.Stsd{avc3: avc}
      _other -> %ExMP4.Box.Stsd{avc1: avc}
    end
  end

  defp sample_description_table(%{media: :h265} = track) do
    hevc = %ExMP4.Box.Hevc{
      tag: track.media_tag && to_string(track.media_tag),
      width: track.width,
      height: track.height,
      hvcC: track.priv_data
    }

    case track.media_tag do
      :hev1 -> %ExMP4.Box.Stsd{hev1: hevc}
      _other -> %ExMP4.Box.Stsd{hvc1: hevc}
    end
  end

  defp sample_description_table(%{media: :vp8} = track) do
    vpx = %ExMP4.Box.VP08{
      width: track.width,
      height: track.height,
      vpcC: track.priv_data
    }

    %ExMP4.Box.Stsd{vp08: vpx}
  end

  defp sample_description_table(%{media: :vp9} = track) do
    vpx = %ExMP4.Box.VP09{
      width: track.width,
      height: track.height,
      vpcC: track.priv_data
    }

    %ExMP4.Box.Stsd{vp09: vpx}
  end

  defp sample_description_table(%{media: :aac} = track) do
    %ExMP4.Box.Stsd{
      mp4a: %ExMP4.Box.Mp4a{
        channel_count: track.channels,
        sample_rate: {track.sample_rate, 0},
        esds: track.priv_data
      }
    }
  end

  defp sample_description_table(%{media: :raw, media_tag: tag} = track) do
    fields = %{
      sample_size: track.priv_data.pcm_sample_size,
      channel_count: track.channels,
      sample_rate: {track.sample_rate, 0},
      pcmC: track.priv_data
    }

    entry =
      case tag do
        :ipcm -> struct!(ExMP4.Box.Ipcm, fields)
        :fpcm -> struct!(ExMP4.Box.Fpcm, fields)
      end

    Map.put(%ExMP4.Box.Stsd{}, tag, entry)
  end

  defp reverse_entries(nil), do: nil
  defp reverse_entries(%{entries: entries} = table), do: %{table | entries: Enum.reverse(entries)}

  defimpl Enumerable do
    def reduce(track, {:suspend, acc}, fun) do
      {:suspended, acc, &reduce(track, &1, fun)}
    end

    def reduce(_track, {:halt, acc}, _fun), do: {:halted, acc}

    # progressive file
    def reduce(%{trex: nil} = track, {:cont, acc}, _fun)
        when track._iter_index > track.sample_count do
      {:done, acc}
    end

    def reduce(%{trex: nil} = track, {:cont, acc}, fun) do
      %{_iter_index: index, _iter_duration: duration} = track

      {stbl, sample_metadata} = Stbl.next_sample(track.sample_table, index, duration)

      sample_metadata = %{sample_metadata | track_id: track.id}

      track = %{
        track
        | sample_table: stbl,
          _iter_index: index + 1,
          _iter_duration: duration + sample_metadata.duration
      }

      reduce(track, fun.(sample_metadata, acc), fun)
    end

    # fragmented file
    def reduce(%{trafs: []}, {:cont, acc}, _fun) do
      {:done, acc}
    end

    def reduce(%{trafs: [traf | rest]} = track, {:cont, acc}, fun) do
      {traf, sample_metadata} = Traf.next_sample(traf, track.trex, track._iter_duration)
      sample_metadata = %{sample_metadata | track_id: track.id}

      track =
        case traf.trun do
          [] -> %{track | trafs: rest}
          _other -> %{track | trafs: [traf | rest]}
        end

      duration = track._iter_duration + sample_metadata.duration

      reduce(%{track | _iter_duration: duration}, fun.(sample_metadata, acc), fun)
    end

    def count(%{trex: trex}) when not is_nil(trex), do: {:error, __MODULE__}
    def count(%{sample_count: count}), do: {:ok, count}

    def member?(_enumerable, _element), do: {:error, __MODULE__}

    def slice(_enumerable), do: {:error, __MODULE__}
  end
end
