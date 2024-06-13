defmodule ExMP4.Sample do
  @moduledoc """
  A struct describing an MP4 sample (a video frame, an audio sample, ...etc)
  """

  @type id :: non_neg_integer()

  @type t :: %__MODULE__{
          track_id: ExMP4.Track.id(),
          pts: non_neg_integer(),
          dts: non_neg_integer(),
          sync?: boolean(),
          payload: binary() | nil
        }

  @enforce_keys [:track_id, :pts, :dts]
  defstruct @enforce_keys ++ [payload: nil, sync?: false]

  @doc """
  Create a new sample
  """
  @spec new(Keyword.t()) :: t()
  def new(opts), do: struct!(__MODULE__, opts)
end
