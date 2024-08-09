defmodule ExMP4.Box.Trex do
  @moduledoc """
  A module representing an `trex` box.

  This sets up default values used by the movie fragments. By setting defaults in this way,
  space and complexity can be saved in each Track Fragment Box.
  """

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          track_id: integer(),
          default_sample_description_index: integer(),
          default_sample_duration: integer(),
          default_sample_size: integer(),
          default_sample_flags: integer()
        }

  defstruct version: 0,
            flags: 0,
            track_id: 0,
            default_sample_description_index: 1,
            default_sample_duration: 0,
            default_sample_size: 0,
            default_sample_flags: 0

  defimpl ExMP4.Box do
    def size(_box) do
      ExMP4.full_box_header_size() + 20
    end

    def parse(
          box,
          <<version::8, flags::24, track_id::32, default_sample_description_index::32,
            default_sample_duration::32, default_sample_size::32, default_sample_flags::32>>
        ) do
      %{
        box
        | version: version,
          flags: flags,
          track_id: track_id,
          default_sample_description_index: default_sample_description_index,
          default_sample_duration: default_sample_duration,
          default_sample_size: default_sample_size,
          default_sample_flags: default_sample_flags
      }
    end

    def serialize(box) do
      <<size(box)::32, "trex", box.version::8, box.flags::24, box.track_id::32,
        box.default_sample_description_index::32, box.default_sample_duration::32,
        box.default_sample_size::32, box.default_sample_flags::32>>
    end
  end
end
