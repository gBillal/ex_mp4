# ExMP4

`ISO-MP4` reader and writer.

This package contains MPEG-4 specifications defined in parts:
* ISO/IEC 14496-12 - ISO Base Media File Format (QuickTime, MPEG-4, etc)
* ISO/IEC 14496-14 - MP4 file format

This package is an alternative to and inspired from [membrane_mp4_plugin](https://github.com/membraneframework/membrane_mp4_plugin). This package differs from the `membrane_mp4_plugin` in that it allows to manipulate mp4 files without the usage of membrane pipelines.

## Installation

The package can be installed by adding `ex_mp4` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_mp4, "~> 0.3.0"}
  ]
end
```

## Usage

check the `examples` folder for usage. 