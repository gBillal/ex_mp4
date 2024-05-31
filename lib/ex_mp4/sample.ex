defmodule ExMP4.Sample do
  @moduledoc """
  A struct describing an MP4 sample (a video frame, an audio sample, ...etc)
  """

  @type id :: non_neg_integer()

  @type t :: %__MODULE__{
          pts: non_neg_integer(),
          dts: non_neg_integer(),
          sync?: boolean(),
          content: binary()
        }

  defstruct [:pts, :dts, :sync?, :content]
end
