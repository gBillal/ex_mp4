defmodule ExMP4.Box.Pcmc do
  @moduledoc """
  A module representing a `pcmC` box.
  """

  @type t :: %__MODULE__{
          version: non_neg_integer(),
          flags: non_neg_integer(),
          format_flags: non_neg_integer(),
          pcm_sample_size: non_neg_integer()
        }

  defstruct [:format_flags, :pcm_sample_size, version: 0, flags: 0]

  defimpl ExMP4.Box, for: ExMP4.Box.Pcmc do
    def size(_box), do: ExMP4.full_box_header_size() + 2

    def parse(box, <<0::8, 0::24, format_flags::8, pcm_sample_size::8>>) do
      %{box | format_flags: format_flags, pcm_sample_size: pcm_sample_size}
    end

    def serialize(box) do
      <<0::32, box.format_flags::8, box.pcm_sample_size::8>>
    end
  end
end
