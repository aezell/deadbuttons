defmodule DeadbuttonsWeb.ScanLive do
  use DeadbuttonsWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       state: :idle,
       url: "",
       buttons: [],
       results: [],
       status_message: nil,
       error: nil
     )}
  end

  @impl true
  def handle_event("scan", %{"url" => url}, socket) do
    url = String.trim(url)

    if url == "" do
      {:noreply, assign(socket, error: "Please enter a URL")}
    else
      url = if String.starts_with?(url, "http"), do: url, else: "https://#{url}"
      Deadbuttons.Scanner.scan_async(url, self())

      {:noreply,
       assign(socket,
         state: :scanning,
         url: url,
         buttons: [],
         results: [],
         status_message: "Fetching page...",
         error: nil
       )}
    end
  end

  def handle_event("reset", _params, socket) do
    {:noreply,
     assign(socket,
       state: :idle,
       url: "",
       buttons: [],
       results: [],
       status_message: nil,
       error: nil
     )}
  end

  @impl true
  def handle_info({:scan_status, :fetching_page}, socket) do
    {:noreply, assign(socket, status_message: "Fetching page...")}
  end

  def handle_info({:scan_status, :parsing}, socket) do
    {:noreply, assign(socket, status_message: "Parsing HTML, looking for 88x31 buttons...")}
  end

  def handle_info({:scan_status, :checking_links}, socket) do
    {:noreply, assign(socket, status_message: "Checking links...")}
  end

  def handle_info({:button_found, button}, socket) do
    buttons = socket.assigns.buttons ++ [button]

    {:noreply,
     assign(socket,
       buttons: buttons,
       status_message: "Found #{length(buttons)} button(s), checking dimensions..."
     )}
  end

  def handle_info({:link_checked, result}, socket) do
    results = socket.assigns.results ++ [result]
    total = length(socket.assigns.buttons)

    {:noreply,
     assign(socket,
       results: results,
       status_message: "Checked #{length(results)}/#{total} links..."
     )}
  end

  def handle_info({:scan_done, _results}, socket) do
    {:noreply, assign(socket, state: :done, status_message: nil)}
  end

  def handle_info({:scan_error, reason}, socket) do
    {:noreply, assign(socket, state: :idle, error: reason, status_message: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-950 text-gray-100">
      <div class="max-w-3xl mx-auto px-4 py-12">
        <header class="text-center mb-10">
          <h1 class="text-4xl font-bold tracking-tight text-white mb-2">deadbuttons</h1>
          <p class="text-gray-400 text-lg">
            Find broken links behind 88&times;31 buttons on any web page
          </p>
        </header>

        <%= if @state == :idle do %>
          <div class="bg-gray-900 rounded-xl p-8 border border-gray-800">
            <form phx-submit="scan" class="space-y-4">
              <div>
                <label for="url" class="block text-sm font-medium text-gray-300 mb-2">
                  Page URL
                </label>
                <input
                  type="text"
                  name="url"
                  id="url"
                  value={@url}
                  placeholder="https://example.com"
                  class="w-full px-4 py-3 bg-gray-800 border border-gray-700 rounded-lg text-white placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent"
                  autofocus
                />
              </div>
              <button
                type="submit"
                class="w-full px-4 py-3 bg-indigo-600 hover:bg-indigo-500 text-white font-medium rounded-lg transition-colors"
              >
                Scan for dead buttons
              </button>
            </form>

            <%= if @error do %>
              <div class="mt-4 p-4 bg-red-900/50 border border-red-700 rounded-lg text-red-300">
                {@error}
              </div>
            <% end %>

            <div class="mt-6 text-sm text-gray-500 space-y-2">
              <p>
                This tool scans a web page for
                <a
                  href="https://en.wikipedia.org/wiki/Web_banner#Standard_sizes"
                  target="_blank"
                  class="text-indigo-400 hover:underline"
                >
                  88&times;31 pixel button images
                </a>
                that are hyperlinked, and checks whether those links are still alive.
              </p>
              <p>
                Common on IndieWeb and SmallWeb sites as blogroll badges and webring buttons.
              </p>
            </div>
          </div>
        <% end %>

        <%= if @state == :scanning do %>
          <div class="bg-gray-900 rounded-xl p-8 border border-gray-800">
            <div class="flex items-center gap-3 mb-6">
              <div class="animate-spin h-5 w-5 border-2 border-indigo-400 border-t-transparent rounded-full">
              </div>
              <span class="text-indigo-300 font-medium">{@status_message}</span>
            </div>

            <p class="text-sm text-gray-500 mb-4">
              Scanning <span class="text-gray-300">{@url}</span>
            </p>

            <%= if @buttons != [] do %>
              <div class="border-t border-gray-800 pt-4">
                <h3 class="text-sm font-medium text-gray-400 mb-3">
                  Buttons found ({length(@buttons)})
                </h3>
                <div class="flex flex-wrap gap-2">
                  <%= for button <- @buttons do %>
                    <img
                      src={button.img_src}
                      width="88"
                      height="31"
                      class="border border-gray-700 rounded"
                      loading="lazy"
                    />
                  <% end %>
                </div>
              </div>
            <% end %>

            <%= if @results != [] do %>
              <div class="border-t border-gray-800 pt-4 mt-4">
                <h3 class="text-sm font-medium text-gray-400 mb-3">
                  Results so far ({length(@results)}/{length(@buttons)})
                </h3>
                {render_results(assigns)}
              </div>
            <% end %>
          </div>
        <% end %>

        <%= if @state == :done do %>
          <div class="bg-gray-900 rounded-xl p-8 border border-gray-800">
            <div class="flex items-center justify-between mb-6">
              <div>
                <h2 class="text-xl font-semibold text-white">Scan complete</h2>
                <p class="text-sm text-gray-400 mt-1">{@url}</p>
              </div>
              <button
                phx-click="reset"
                class="px-4 py-2 bg-gray-800 hover:bg-gray-700 text-gray-300 rounded-lg text-sm transition-colors"
              >
                Scan another
              </button>
            </div>

            <%= if @results == [] do %>
              <div class="text-center py-8 text-gray-500">
                <p class="text-lg">No 88&times;31 buttons found on this page.</p>
              </div>
            <% else %>
              <div class="mb-4">
                {summary_stats(assigns)}
              </div>
              {render_results(assigns)}
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_results(assigns) do
    ~H"""
    <div class="space-y-3">
      <%= for result <- @results do %>
        <div class="flex items-center gap-4 p-3 bg-gray-800/50 rounded-lg border border-gray-700/50">
          <img
            src={result.img_src}
            width="88"
            height="31"
            class="border border-gray-600 rounded flex-shrink-0"
            loading="lazy"
          />
          <div class="min-w-0 flex-1">
            <a
              href={result.link_href}
              target="_blank"
              rel="noopener"
              class="text-sm text-indigo-400 hover:underline truncate block"
            >
              {result.link_href}
            </a>
            <%= if result.error do %>
              <span class="text-xs text-gray-500">{result.error}</span>
            <% end %>
          </div>
          <div class="flex-shrink-0">
            {status_badge(result)}
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp status_badge(result) do
    case result.link_status do
      :alive ->
        Phoenix.HTML.raw("""
        <span class="inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs font-medium bg-green-900/50 text-green-300 border border-green-700/50">
          #{result.http_status} OK
        </span>
        """)

      :dead ->
        Phoenix.HTML.raw("""
        <span class="inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs font-medium bg-red-900/50 text-red-300 border border-red-700/50">
          #{result.http_status} Dead
        </span>
        """)

      :redirect ->
        Phoenix.HTML.raw("""
        <span class="inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs font-medium bg-yellow-900/50 text-yellow-300 border border-yellow-700/50">
          #{result.http_status} Redirect
        </span>
        """)

      :error ->
        Phoenix.HTML.raw("""
        <span class="inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs font-medium bg-gray-700/50 text-gray-300 border border-gray-600/50">
          Error
        </span>
        """)
    end
  end

  defp summary_stats(assigns) do
    alive = Enum.count(assigns.results, &(&1.link_status == :alive))
    dead = Enum.count(assigns.results, &(&1.link_status == :dead))
    errors = Enum.count(assigns.results, &(&1.link_status == :error))
    redirects = Enum.count(assigns.results, &(&1.link_status == :redirect))
    total = length(assigns.results)

    assigns =
      assign(assigns,
        alive: alive,
        dead: dead,
        errors: errors,
        redirects: redirects,
        total: total
      )

    ~H"""
    <div class="flex flex-wrap gap-4 text-sm">
      <span class="text-gray-400">{@total} buttons checked:</span>
      <span class="text-green-400">{@alive} alive</span>
      <%= if @dead > 0 do %>
        <span class="text-red-400">{@dead} dead</span>
      <% end %>
      <%= if @redirects > 0 do %>
        <span class="text-yellow-400">{@redirects} redirect</span>
      <% end %>
      <%= if @errors > 0 do %>
        <span class="text-gray-400">{@errors} error</span>
      <% end %>
    </div>
    """
  end
end
