defmodule Deadbuttons.Scanner do
  @moduledoc """
  Orchestrates scanning a page for 88x31 button images and checking their links.
  Sends progress messages to the calling process.
  """

  alias Deadbuttons.ImageUtil

  # Keep concurrency low to avoid OOM on small machines
  @max_concurrency 3
  @task_timeout 12_000
  @max_candidates 100
  # Only need first 1KB to read image dimensions
  @image_header_bytes 1024
  # Cap page body at 2MB
  @max_page_bytes 2 * 1024 * 1024

  @doc """
  Starts an async scan of the given URL. Sends messages to `pid`:
  - `{:scan_status, :fetching_page}`
  - `{:scan_status, :parsing}`
  - `{:button_found, button_map}`
  - `{:link_checked, result_map}`
  - `{:scan_done, results}`
  - `{:scan_error, reason}`
  """
  def scan_async(url, pid) do
    Task.start(fn ->
      try do
        send(pid, {:scan_status, :fetching_page})
        results = scan(url, pid)
        send(pid, {:scan_done, results})
      rescue
        e -> send(pid, {:scan_error, Exception.message(e)})
      end
    end)
  end

  defp scan(url, pid) do
    html = fetch_page(url)
    send(pid, {:scan_status, :parsing})

    candidates =
      html
      |> find_button_candidates(url)
      |> Enum.take(@max_candidates)

    buttons =
      candidates
      |> Task.async_stream(
        fn candidate -> check_if_88x31(candidate) end,
        max_concurrency: @max_concurrency,
        timeout: @task_timeout,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, {:ok, button}} ->
          send(pid, {:button_found, button})
          [button]
        _ ->
          []
      end)

    send(pid, {:scan_status, :checking_links})

    results =
      buttons
      |> Task.async_stream(
        fn button -> check_link(button) end,
        max_concurrency: @max_concurrency,
        timeout: @task_timeout,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, result} ->
          send(pid, {:link_checked, result})
          [result]
        _ ->
          []
      end)

    results
  end

  defp fetch_page(url) do
    resp =
      Req.get!(url,
        redirect: true,
        max_redirects: 5,
        connect_options: [timeout: 8_000],
        receive_timeout: 10_000,
        max_body: @max_page_bytes
      )

    if resp.status == 200 do
      resp.body
    else
      raise "Failed to fetch page: HTTP #{resp.status}"
    end
  end

  defp find_button_candidates(html, base_url) do
    {:ok, doc} = Floki.parse_document(html)

    # Find all <a> tags that contain <img> tags
    doc
    |> Floki.find("a")
    |> Enum.flat_map(fn a_node ->
      href = Floki.attribute([a_node], "href") |> List.first()
      imgs = Floki.find([a_node], "img")

      Enum.map(imgs, fn img_node ->
        src = Floki.attribute([img_node], "src") |> List.first()
        width_attr = Floki.attribute([img_node], "width") |> List.first()
        height_attr = Floki.attribute([img_node], "height") |> List.first()

        %{
          img_src: resolve_url(src, base_url),
          link_href: resolve_url(href, base_url),
          width_attr: width_attr,
          height_attr: height_attr
        }
      end)
    end)
    |> Enum.filter(fn c -> c.img_src != nil and c.link_href != nil end)
    |> Enum.uniq_by(fn c -> {c.img_src, c.link_href} end)
  end

  defp check_if_88x31(candidate) do
    # First check HTML attributes
    if candidate.width_attr == "88" and candidate.height_attr == "31" do
      {:ok, Map.take(candidate, [:img_src, :link_href])}
    else
      # Fetch just the image header bytes to check dimensions
      case fetch_image_header(candidate.img_src) do
        {:ok, data} ->
          if ImageUtil.is_88x31?(data) do
            {:ok, Map.take(candidate, [:img_src, :link_href])}
          else
            :skip
          end

        :error ->
          :skip
      end
    end
  end

  # Fetch only the first N bytes of an image — enough to read dimension headers
  defp fetch_image_header(url) do
    try do
      resp =
        Req.get!(url,
          redirect: true,
          max_redirects: 5,
          connect_options: [timeout: 8_000],
          receive_timeout: 8_000,
          headers: [{"range", "bytes=0-#{@image_header_bytes - 1}"}],
          raw: true
        )

      # 200 = full body (server ignored Range), 206 = partial content
      if resp.status in [200, 206] do
        # If server returned full body, only keep what we need
        body = if byte_size(resp.body) > @image_header_bytes do
          binary_part(resp.body, 0, @image_header_bytes)
        else
          resp.body
        end
        {:ok, body}
      else
        :error
      end
    rescue
      _ -> :error
    end
  end

  defp check_link(button) do
    url = button.link_href

    try do
      # Try HEAD first (no body), fall back to GET with body size cap
      resp =
        try do
          Req.head!(url,
            redirect: true,
            max_redirects: 5,
            connect_options: [timeout: 8_000],
            receive_timeout: 8_000
          )
        rescue
          _ ->
            # Some servers reject HEAD; do a GET but cap the body
            Req.get!(url,
              redirect: true,
              max_redirects: 5,
              connect_options: [timeout: 8_000],
              receive_timeout: 8_000,
              max_body: 4_096
            )
        end

      status = classify_status(resp.status)

      %{
        img_src: button.img_src,
        link_href: button.link_href,
        link_status: status,
        http_status: resp.status,
        error: nil
      }
    rescue
      e ->
        %{
          img_src: button.img_src,
          link_href: button.link_href,
          link_status: :error,
          http_status: nil,
          error: Exception.message(e)
        }
    end
  end

  defp classify_status(status) when status >= 200 and status < 300, do: :alive
  defp classify_status(status) when status >= 300 and status < 400, do: :redirect
  defp classify_status(_), do: :dead

  defp resolve_url(nil, _base), do: nil
  defp resolve_url("", _base), do: nil

  defp resolve_url(url, base) do
    cond do
      String.starts_with?(url, "http://") or String.starts_with?(url, "https://") ->
        url

      String.starts_with?(url, "//") ->
        "https:" <> url

      String.starts_with?(url, "/") ->
        base_uri = URI.parse(base)
        "#{base_uri.scheme}://#{base_uri.host}#{url}"

      true ->
        # Relative URL
        base
        |> URI.parse()
        |> URI.merge(url)
        |> URI.to_string()
    end
  end
end
