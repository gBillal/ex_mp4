defmodule ExMP4.Box.MovieFragment do
  @moduledoc """
  A module containing a function for assembling an MPEG-4 movie fragment (moof) box.
  """
  alias ExMP4.Container
  alias ExMP4.Track.Fragment

  @doc """
  Creates a new `moof` box from the `ExMP4.Track.Fragment` fragments.
  """
  @spec assemble([Fragment.t()], integer()) :: Container.t()
  def assemble(fragments, sequence_number) do
    [
      moof: %{
        children:
          [
            mfhd: %{
              fields: %{
                version: 0,
                flags: 0,
                sequence_number: sequence_number
              }
            }
          ] ++ Enum.flat_map(fragments, &track_fragment/1)
      }
    ]
  end

  @doc """
  Unpacks a `moof` box into a list of `ExMP4.Track.Fragment` fragments.
  """
  @spec unpack(Container.t()) :: [Fragment.t()]
  def unpack(moof) do
    get_in(moof, [:moof, :children])
    |> Keyword.get_values(:traf)
    |> Enum.map(fn traf ->
      tfhd = get_in(traf, [:children, :tfhd])

      fragment =
        tfhd.fields
        |> Map.drop([:flags, :version])
        |> Map.new(fn {key, value} -> {key, nullify(value)} end)
        |> then(&struct!(Fragment, &1))

      traf.children
      |> Keyword.get_values(:trun)
      |> Enum.map(&unpack_run/1)
      |> Enum.reduce(fragment, &Fragment.add_run(&2, &1))
    end)
  end

  @spec update_base_data_offsets(Container.t(), %{(track_id :: integer()) => offset :: integer()}) ::
          Container.t()
  def update_base_data_offsets(movie_fragment, offsets) do
    moof_children = get_in(movie_fragment, [:moof, :children])

    trafs =
      moof_children
      |> Keyword.get_values(:traf)
      |> Enum.map(fn traf_box ->
        Container.update_box(traf_box.children, [:tfhd], [:fields], fn header ->
          %{header | base_data_offset: offsets[header.track_id]}
        end)
      end)
      |> Enum.map(&{:traf, %{children: &1, fields: %{}}})

    moof_children
    |> Keyword.delete(:traf)
    |> Keyword.merge(trafs)
    |> then(&[moof: %{children: &1, fields: %{}}])
  end

  defp track_fragment(fragment) do
    [
      traf: %{
        children:
          [
            tfhd: %{
              children: [],
              fields: %{
                version: 0,
                flags: traf_header_flags(fragment),
                track_id: fragment.track_id,
                base_data_offset: fragment.base_data_offset,
                default_sample_description_index: fragment.default_sample_description_index,
                default_sample_duration: fragment.default_sample_duration,
                default_sample_size: fragment.default_sample_size,
                default_sample_flags: fragment.default_sample_flags
              }
            },
            tfdt: %{
              fields: %{
                version: 1,
                flags: 0,
                base_media_decode_time: fragment.base_media_decode_time
              }
            }
          ] ++ Enum.flat_map(fragment.runs, &track_run/1)
      }
    ]
  end

  defp track_run(run) do
    [
      trun: %{
        children: [],
        fields: %{
          version: 0,
          flags: trun_flags(run),
          sample_count: run.sample_count,
          samples: map_samples(run)
        }
      }
    ]
  end

  defp traf_header_flags(fragment) do
    import Bitwise

    flags = 1

    flags = if fragment.default_sample_description_index, do: flags ||| 0x02, else: flags
    flags = if fragment.default_sample_duration, do: flags ||| 0x08, else: flags
    flags = if fragment.default_sample_size, do: flags ||| 0x10, else: flags
    if fragment.default_sample_flags, do: flags ||| 0x20, else: flags
  end

  defp trun_flags(run) do
    import Bitwise

    flags = 0

    flags = if run.sample_durations, do: flags ||| 0x100, else: flags
    flags = if run.sample_sizes, do: flags ||| 0x200, else: flags
    flags = if run.sync_samples, do: flags ||| 0x400, else: flags
    if run.sample_composition_offsets, do: flags ||| 0x800, else: flags
  end

  defp map_samples(run) do
    %{
      sample_durations: durations,
      sample_sizes: sizes,
      sample_composition_offsets: offsets,
      sync_samples: flags
    } = run

    durations = if durations, do: durations, else: List.duplicate(nil, run.sample_count)
    sizes = if sizes, do: sizes, else: List.duplicate(nil, run.sample_count)
    offsets = if offsets, do: offsets, else: List.duplicate(nil, run.sample_count)

    flags =
      if flags do
        for <<sync::1 <- flags>>, do: <<0::15, sync::1, 0::16>>
      else
        List.duplicate(nil, run.sample_count)
      end

    List.zip([durations, sizes, flags, offsets])
    |> Enum.map(fn {duration, size, flag, offset} ->
      %{
        sample_duration: duration,
        sample_size: size,
        sample_flags: flag,
        sample_composition_offset: offset
      }
    end)
  end

  defp unpack_run(%{fields: fields}) do
    {durations, sizes, flags, composition_offsets} =
      Enum.reduce(
        fields.samples,
        {[], [], <<>>, []},
        fn sample, {durations, sizes, flags, composition_offsets} ->
          flags =
            case sample.sample_flags do
              [] -> flags
              <<_prefix::15, sync::1, _rest::binary>> -> <<flags::bitstring, sync::1>>
            end

          {
            prepend(sample.sample_duration, durations),
            prepend(sample.sample_size, sizes),
            flags,
            prepend(sample.sample_composition_offset, composition_offsets)
          }
        end
      )

    %Fragment.Run{
      sample_count: fields.sample_count,
      first_sample_flags: nullify(fields.first_sample_flags),
      sample_durations: Enum.reverse(durations) |> nullify(),
      sample_sizes: Enum.reverse(sizes) |> nullify(),
      sync_samples: flags,
      sample_composition_offsets: Enum.reverse(composition_offsets) |> nullify()
    }
  end

  defp nullify([]), do: nil
  defp nullify(value), do: value

  defp prepend([], list), do: list
  defp prepend(value, list), do: [value | list]
end
