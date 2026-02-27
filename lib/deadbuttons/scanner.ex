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
  # Only need first 512 bytes to read image dimensions
  # (GIF needs 10, PNG needs 24, JPEG needs ~500 worst case)
  @image_header_bytes 512

  def scan_async(url, pid) do
    case Deadbuttons.ScanLimiter.acquire() do
      :ok ->
        Task.start(fn ->
          try do
            send(pid, {:scan_status, :fetching_page})
            results = scan(url, pid)
            send(pid, {:scan_done, results})
          rescue
            e -> send(pid, {:scan_error, Exception.message(e)})
          after
            Deadbuttons.ScanLimiter.release()
          end
        end)

      :busy ->
        send(pid, {:scan_error, "The aardvark is sniffing too many pages right now! Try again in a moment."})
        {:ok, nil}
    end
  end

  defp scan(url, pid) do
    html = fetch_page(url)
    send(pid, {:scan_status, :parsing})

    candidates = find_button_candidates(html, url)

    # Let GC reclaim the HTML body and parsed doc
    :erlang.garbage_collect()

    candidates = Enum.take(candidates, @max_candidates)

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
        receive_timeout: 10_000
      )

    if resp.status == 200 do
      resp.body
    else
      raise "Failed to fetch page: HTTP #{resp.status}"
    end
  end

  defp find_button_candidates(html, base_url) do
    {:ok, doc} = Floki.parse_document(html)

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
    if candidate.width_attr == "88" and candidate.height_attr == "31" do
      {:ok, Map.take(candidate, [:img_src, :link_href])}
    else
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

  # Stream only the first @image_header_bytes of the image, then halt.
  # This works regardless of whether the server honors Range headers.
  defp fetch_image_header(url) do
    try do
      resp =
        Req.get!(url,
          redirect: true,
          max_redirects: 5,
          connect_options: [timeout: 8_000],
          receive_timeout: 8_000,
          raw: true,
          into: fn {:data, data}, {req, resp} ->
            acc = Map.get(resp.headers, "x-acc", <<>>)
            acc = acc <> data

            if byte_size(acc) >= @image_header_bytes do
              {:halt, {req, put_in(resp.headers["x-acc"], acc)}}
            else
              {:cont, {req, put_in(resp.headers["x-acc"], acc)}}
            end
          end
        )

      if resp.status in [200, 206] do
        {:ok, Map.get(resp.headers, "x-acc", <<>>)}
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
      # Try HEAD first (no body)
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
            # Some servers reject HEAD; do a GET but only read the status,
            # halt immediately to avoid downloading the body.
            Req.get!(url,
              redirect: true,
              max_redirects: 5,
              connect_options: [timeout: 8_000],
              receive_timeout: 8_000,
              into: fn {:data, _data}, {req, resp} ->
                {:halt, {req, resp}}
              end
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
        base
        |> URI.parse()
        |> URI.merge(url)
        |> URI.to_string()
    end
  end
end
