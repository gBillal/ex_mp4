defmodule ExMP4.Box.MovieExtendsBox do
  @moduledoc """
  The module provides a function that assembles an MPEG-4 movie extends box (`mvex` atom).

  The movie extends box provides information about movie fragment boxes in case when
  media data is fragmented (for example in CMAF). It has to contain as many track
  extends box (`trex` atoms) as there are tracks in the movie box.

  For more information about the movie extends box, refer to [ISO/IEC 14496-12](https://www.iso.org/standard/74428.html).
  """
  alias ExMP4.{Container, Track}

  @spec assemble([Track.t()]) :: Container.t()
  @spec assemble([Track.t()], integer() | nil) :: Container.t()
  def assemble(tracks, total_duration \\ nil) do
    mehd =
      if total_duration do
        [mehd: %{fields: %{version: 0, flags: 0, fragment_duration: total_duration}}]
      else
        []
      end

    [
      mvex: %{
        children: mehd ++ Enum.flat_map(tracks, &track_extends_box/1)
      }
    ]
  end

  defp track_extends_box(track) do
    [
      trex: %{
        fields: %{
          version: 0,
          flags: 0,
          track_id: track.id,
          default_sample_description_index: 1,
          default_sample_duration: 0,
          default_sample_size: 0,
          default_sample_flags: 0
        }
      }
    ]
  end
end
