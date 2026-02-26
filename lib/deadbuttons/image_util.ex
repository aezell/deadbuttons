defmodule Deadbuttons.ImageUtil do
  @moduledoc """
  Parse binary image headers to extract dimensions.
  Supports GIF, PNG, and JPEG formats using pure Elixir pattern matching.
  """

  @doc """
  Returns `{:ok, {width, height}}` or `:error` given raw image binary data.
  """
  def dimensions(data) when is_binary(data) do
    cond do
      gif?(data) -> gif_dimensions(data)
      png?(data) -> png_dimensions(data)
      jpeg?(data) -> jpeg_dimensions(data)
      true -> :error
    end
  end

  def dimensions(_), do: :error

  @doc """
  Returns true if the image is 88x31 pixels.
  """
  def is_88x31?(data) do
    case dimensions(data) do
      {:ok, {88, 31}} -> true
      _ -> false
    end
  end

  # GIF: starts with "GIF87a" or "GIF89a"
  # Bytes 6-7: width (uint16 LE), bytes 8-9: height (uint16 LE)
  defp gif?(<<"GIF8", _, "a", _::binary>>), do: true
  defp gif?(_), do: false

  defp gif_dimensions(<<"GIF8", _, "a", width::little-unsigned-16, height::little-unsigned-16, _::binary>>) do
    {:ok, {width, height}}
  end

  defp gif_dimensions(_), do: :error

  # PNG: starts with 8-byte signature
  # IHDR chunk at byte 16: width (uint32 BE), height (uint32 BE)
  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  defp png?(@png_signature <> _), do: true
  defp png?(_), do: false

  defp png_dimensions(<<@png_signature, _ihdr_length::32, "IHDR", width::unsigned-32, height::unsigned-32, _::binary>>) do
    {:ok, {width, height}}
  end

  defp png_dimensions(_), do: :error

  # JPEG: starts with 0xFF 0xD8
  defp jpeg?(<<0xFF, 0xD8, _::binary>>), do: true
  defp jpeg?(_), do: false

  defp jpeg_dimensions(<<0xFF, 0xD8, rest::binary>>) do
    scan_jpeg_markers(rest)
  end

  defp jpeg_dimensions(_), do: :error

  # Scan through JPEG markers looking for SOF markers (0xC0-0xCF, excluding 0xC4 and 0xC8)
  defp scan_jpeg_markers(<<0xFF, marker, _length::16, _precision::8, height::16, width::16, _::binary>>)
       when marker in [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF] do
    {:ok, {width, height}}
  end

  defp scan_jpeg_markers(<<0xFF, _marker, length::16, rest::binary>>) when length >= 2 do
    skip = length - 2

    case rest do
      <<_::binary-size(skip), remaining::binary>> -> scan_jpeg_markers(remaining)
      _ -> :error
    end
  end

  # Skip padding bytes (0xFF without marker)
  defp scan_jpeg_markers(<<0xFF, 0xFF, rest::binary>>) do
    scan_jpeg_markers(<<0xFF, rest::binary>>)
  end

  defp scan_jpeg_markers(_), do: :error
end
