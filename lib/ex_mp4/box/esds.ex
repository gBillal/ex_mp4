defmodule ExMP4.Box.Esds do
  @moduledoc """
  A module representing an `esds` box.
  """

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          es_descriptor: binary()
        }

  defstruct version: 0, flags: 0, es_descriptor: nil

  if Code.ensure_loaded?(MediaCodecs) do
    alias MediaCodecs.MPEG4.{DecoderConfigDescriptor, ESDescriptor, SLConfigDescriptor}

    @doc """
    Creates a new `esds` box with the given audio specific configuration.

    Only available if [MediaCodecs](https://hex.pm/packages/media_codecs) is installed.
    """
    @spec new(binary()) :: t()
    def new(audio_specific_config) do
      es_descriptor = %ESDescriptor{
        dec_config_descr: %DecoderConfigDescriptor{
          # object_type_indication: Audio ISO/IEC 14496-3
          object_type_indication: 0x40,
          up_stream: false,
          # stream_type: audio stream
          stream_type: 5,
          buffer_size_db: 0,
          max_bitrate: 0,
          avg_bitrate: 0,
          decoder_specific_info: audio_specific_config
        },
        sl_config_descr: %SLConfigDescriptor{predefined: 2}
      }

      %__MODULE__{es_descriptor: ESDescriptor.serialize(es_descriptor)}
    end

    @doc """
    Gets the audio specific configuration from the `esds` box.
    """
    @spec audio_specific_config(t()) :: binary()
    def audio_specific_config(esds) do
      descriptor = ESDescriptor.parse(esds.es_descriptor)
      descriptor.dec_config_descr.decoder_specific_info
    end
  end

  defimpl ExMP4.Box do
    def size(box) do
      ExMP4.full_box_header_size() + byte_size(box.es_descriptor)
    end

    def parse(box, <<version::8, flags::24, es_descriptor::binary>>) do
      %{box | version: version, flags: flags, es_descriptor: es_descriptor}
    end

    def serialize(box) do
      [<<size(box)::32, "esds">>, box.version, <<box.flags::24>>, box.es_descriptor]
    end
  end
end
