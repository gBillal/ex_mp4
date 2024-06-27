defmodule ExMP4.SampleMetadata do
  @moduledoc """
  A struct describing the metadata of a sample.
  """

  @typedoc """
  Sample metadata struct.

    * `track_id` - The track id of the sample.
    * `dts` - The decoding time of the sample in track `timescale` units.
    * `pts` - The presentation (compoistion) time of the sample in track `timescale` units.
    * `sync?` - Indicates wether the sample is a sync or rap (random access point).
    * `duration` -  The duration of the sample in track `timescale` units.
    * `size` - The size of the sample.
    * `offset` - The offset of the sample in the container.
  """
  @type t :: %__MODULE__{
          track_id: integer() | nil,
          dts: integer(),
          pts: integer(),
          sync?: boolean(),
          duration: integer(),
          size: integer(),
          offset: integer()
        }

  defstruct track_id: nil, dts: 0, pts: 0, sync?: false, duration: 0, size: 0, offset: 0
end
