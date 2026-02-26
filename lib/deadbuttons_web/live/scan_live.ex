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
       error: nil,
       filter: nil
     )}
  end

  @impl true
  def handle_event("scan", %{"url" => url}, socket) do
    url = String.trim(url)

    cond do
      url == "" ->
        {:noreply, assign(socket, error: "The aardvark needs a URL to sniff out!")}

      not valid_url?(url) ->
        {:noreply, assign(socket, error: "That doesn't look like a URL. Try something like https://example.com")}

      true ->
        url = if String.starts_with?(url, "http"), do: url, else: "https://#{url}"
        Deadbuttons.Scanner.scan_async(url, self())

        {:noreply,
         assign(socket,
           state: :scanning,
           url: url,
           buttons: [],
           results: [],
           status_message: "Snout down, digging in...",
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
       error: nil,
       filter: nil
     )}
  end

  def handle_event("filter", %{"status" => "all"}, socket) do
    {:noreply, assign(socket, filter: nil)}
  end

  def handle_event("filter", %{"status" => status}, socket) do
    filter = String.to_existing_atom(status)
    # Toggle off if clicking the same filter
    filter = if socket.assigns.filter == filter, do: nil, else: filter
    {:noreply, assign(socket, filter: filter)}
  end

  @impl true
  def handle_info({:scan_status, :fetching_page}, socket) do
    {:noreply, assign(socket, status_message: "Snout down, digging in...")}
  end

  def handle_info({:scan_status, :parsing}, socket) do
    {:noreply, assign(socket, status_message: "Rummaging through the ant hill for tiny buttons...")}
  end

  def handle_info({:scan_status, :checking_links}, socket) do
    {:noreply, assign(socket, status_message: "Licking each link to see if it's still tasty...")}
  end

  def handle_info({:button_found, button}, socket) do
    buttons = socket.assigns.buttons ++ [button]

    {:noreply,
     assign(socket,
       buttons: buttons,
       status_message: "Sniffed out #{length(buttons)} button#{if length(buttons) != 1, do: "s", else: ""}!"
     )}
  end

  def handle_info({:link_checked, result}, socket) do
    results = socket.assigns.results ++ [result]
    total = length(socket.assigns.buttons)

    {:noreply,
     assign(socket,
       results: results,
       status_message: "Taste-tested #{length(results)} of #{total} links..."
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
    <div class="min-h-screen animated-bg font-mono text-white">
      <div class="max-w-2xl mx-auto px-4 py-10">
        <%!-- Header with mascot --%>
        <header class="text-center mb-8">
          <div class="inline-block mb-4">
            <img
              src={~p"/images/aardvark.svg"}
              alt="Deadbuttons Aardvark"
              width="140"
              height="140"
              class={if @state == :scanning, do: "aardvark-sniff", else: ""}
            />
          </div>
          <h1
            class="text-5xl sm:text-6xl font-black uppercase tracking-tight"
            style="color: #ffee11; text-shadow: 4px 4px 0 #aa00ee, -1px -1px 0 #000, 1px -1px 0 #000, -1px 1px 0 #000, 1px 1px 0 #000;"
          >
            deadbuttons
          </h1>
          <p class="text-lg font-bold mt-2" style="color: #f11cac;">
            an aardvark that sniffs out
            <span class="bg-[#aa00ee] text-[#ffee11] px-2 py-0.5 border-2 border-black">dead 88&times;31 buttons</span>
          </p>
        </header>

        <%= if @state == :idle do %>
          <div class="bg-black/80 border-4 border-[#aa00ee] p-8 shadow-[8px_8px_0_0_#f11cac]">
            <form phx-submit="scan" class="space-y-5">
              <div>
                <label for="url" class="block text-sm font-black uppercase tracking-wide mb-2 text-[#ffee11]">
                  Feed me a URL
                </label>
                <input
                  type="text"
                  name="url"
                  id="url"
                  value={@url}
                  placeholder="https://cool-site-with-buttons.neocities.org"
                  class="w-full px-4 py-3 bg-[#1a0030] border-3 border-[#aa00ee] text-white placeholder-white/30 font-mono text-lg focus:outline-none focus:border-[#ffee11] focus:shadow-[0_0_10px_#ffee11]"
                  autofocus
                />
              </div>
              <button
                type="submit"
                class="w-full px-4 py-4 bg-[#aa00ee] hover:bg-[#cc44ff] active:translate-x-1 active:translate-y-1 active:shadow-none text-[#ffee11] text-xl font-black uppercase border-4 border-[#ffee11] shadow-[4px_4px_0_0_#f11cac] transition-all cursor-pointer"
              >
                Release the Aardvark
              </button>
            </form>

            <%= if @error do %>
              <div class="mt-5 p-4 bg-[#f11cac] border-4 border-[#ffee11] text-white font-bold shadow-[4px_4px_0_0_#aa00ee]">
                {@error}
              </div>
            <% end %>

            <div class="mt-8 space-y-3 text-sm text-white/70">
              <p class="font-bold text-[#0088ff]">What does this aardvark do?</p>
              <p>
                It burrows into any web page and hunts for those
                <a
                  href="https://en.wikipedia.org/wiki/Web_banner#Standard_sizes"
                  target="_blank"
                  class="text-[#ffee11] border-b-2 border-[#ffee11] hover:bg-[#ffee11] hover:text-black transition-colors"
                >
                  tiny 88&times;31 pixel buttons
                </a>
                &mdash; the ones IndieWeb folks use for blogrolls, webrings, and friend badges.
              </p>
              <p>
                Then it licks every link to check if the site on the other end is still alive.
                Like an anteater, but for dead links. An <em class="text-[#f11cac]">aard</em><em class="text-[#aa00ee]">vark</em>, if you will.
              </p>
              <p class="text-white/30">
                No cookies. No tracking. No anthill left unturned.
              </p>
            </div>
          </div>
        <% end %>

        <%= if @state == :scanning do %>
          <div class="bg-black/80 border-4 border-[#f11cac] p-8 shadow-[8px_8px_0_0_#aa00ee]">
            <div class="flex items-center gap-3 mb-5">
              <span class="text-3xl aardvark-lick">👅</span>
              <span class="font-black text-lg text-[#ffee11]">{@status_message}</span>
            </div>

            <p class="text-sm font-bold text-white/40 mb-5 break-all">
              Burrowing into <span class="text-[#0088ff]">{@url}</span>
            </p>

            <%= if @buttons != [] do %>
              <div class="border-t-4 border-[#aa00ee] pt-4">
                <h3 class="text-sm font-black uppercase tracking-wide mb-3 text-[#f11cac]">
                  Unearthed {length(@buttons)} button{if length(@buttons) != 1, do: "s", else: ""}
                </h3>
                <div class="flex flex-wrap gap-2">
                  <%= for button <- @buttons do %>
                    <img
                      src={button.img_src}
                      width="88"
                      height="31"
                      class="border-2 border-[#ffee11]"
                      loading="lazy"
                    />
                  <% end %>
                </div>
              </div>
            <% end %>

            <%= if @results != [] do %>
              <div class="border-t-4 border-[#aa00ee] pt-4 mt-5">
                <h3 class="text-sm font-black uppercase tracking-wide mb-3 text-[#f11cac]">
                  Taste-tested {length(@results)} of {length(@buttons)}
                </h3>
                {render_results(assigns)}
              </div>
            <% end %>
          </div>
        <% end %>

        <%= if @state == :done do %>
          <div class="bg-black/80 border-4 border-[#ffee11] p-8 shadow-[8px_8px_0_0_#aa00ee]">
            <div class="flex items-start justify-between mb-6 gap-4">
              <div>
                <h2 class="text-2xl font-black uppercase text-[#ffee11]">The aardvark has spoken</h2>
                <p class="text-sm font-bold text-white/40 mt-1 break-all">{@url}</p>
              </div>
              <button
                phx-click="reset"
                class="px-4 py-2 bg-[#f11cac] hover:bg-[#ff44cc] text-white font-black uppercase text-sm border-3 border-[#ffee11] shadow-[3px_3px_0_0_#aa00ee] active:translate-x-0.5 active:translate-y-0.5 active:shadow-none transition-all whitespace-nowrap cursor-pointer"
              >
                Dig Again
              </button>
            </div>

            <%= if @results == [] do %>
              <div class="text-center py-10 border-t-4 border-[#aa00ee]">
                <p class="text-4xl mb-3">🕳️</p>
                <p class="text-xl font-black text-[#ffee11]">Empty burrow!</p>
                <p class="text-white/50 font-bold mt-1">No 88&times;31 buttons found on this page.</p>
              </div>
            <% else %>
              <div class="mb-5">
                {summary_stats(assigns)}
              </div>
              {render_results(assigns)}
            <% end %>
          </div>
        <% end %>

        <footer class="text-center mt-10 text-xs font-bold text-white/20">
          no ants were harmed in the making of this website
        </footer>
      </div>
    </div>
    """
  end

  defp render_results(assigns) do
    filtered =
      if assigns.filter do
        Enum.filter(assigns.results, &(&1.link_status == assigns.filter))
      else
        assigns.results
      end

    assigns = assign(assigns, filtered: filtered)

    ~H"""
    <div class="space-y-3">
      <%= for result <- @filtered do %>
        <div class="flex items-center gap-4 p-3 border-3 border-[#aa00ee] bg-[#1a0030]/80">
          <img
            src={result.img_src}
            width="88"
            height="31"
            class="border-2 border-[#f11cac] flex-shrink-0"
            loading="lazy"
          />
          <div class="min-w-0 flex-1">
            <a
              href={result.link_href}
              target="_blank"
              rel="noopener"
              class="text-sm font-bold text-[#0088ff] hover:text-[#ffee11] truncate block break-all transition-colors"
            >
              {result.link_href}
            </a>
            <%= if result.error do %>
              <span class="text-xs font-bold text-white/30">{result.error}</span>
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
        <span class="inline-flex items-center px-3 py-1 text-xs font-black uppercase bg-[#00cc66] text-black border-3 border-black shadow-[2px_2px_0_0_#aa00ee]">
          #{result.http_status} Alive
        </span>
        """)

      :dead ->
        Phoenix.HTML.raw("""
        <span class="inline-flex items-center px-3 py-1 text-xs font-black uppercase bg-[#f11cac] text-white border-3 border-black shadow-[2px_2px_0_0_#ffee11]">
          #{result.http_status} Dead
        </span>
        """)

      :redirect ->
        Phoenix.HTML.raw("""
        <span class="inline-flex items-center px-3 py-1 text-xs font-black uppercase bg-[#ffee11] text-black border-3 border-black shadow-[2px_2px_0_0_#aa00ee]">
          #{result.http_status} Wandered Off
        </span>
        """)

      :error ->
        Phoenix.HTML.raw("""
        <span class="inline-flex items-center px-3 py-1 text-xs font-black uppercase bg-[#0088ff] text-white border-3 border-black shadow-[2px_2px_0_0_#f11cac]">
          Mystery Hole
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
    <div class="flex flex-wrap gap-3 text-sm font-black">
      <button
        phx-click="filter"
        phx-value-status="all"
        class={"px-3 py-1 border-3 border-[#aa00ee] bg-black/50 text-white shadow-[2px_2px_0_0_#f11cac] cursor-pointer transition-all " <> if(@filter == nil, do: "ring-2 ring-white scale-110", else: "hover:scale-105")}
      >
        {@total} sniffed
      </button>
      <button
        phx-click="filter"
        phx-value-status="alive"
        class={"px-3 py-1 border-3 border-black bg-[#00cc66] text-black shadow-[2px_2px_0_0_#aa00ee] cursor-pointer transition-all " <> if(@filter == :alive, do: "ring-2 ring-white scale-110", else: "hover:scale-105")}
      >
        {@alive} alive
      </button>
      <%= if @dead > 0 do %>
        <button
          phx-click="filter"
          phx-value-status="dead"
          class={"px-3 py-1 border-3 border-black bg-[#f11cac] text-white shadow-[2px_2px_0_0_#ffee11] cursor-pointer transition-all " <> if(@filter == :dead, do: "ring-2 ring-white scale-110", else: "hover:scale-105")}
        >
          {@dead} dead
        </button>
      <% end %>
      <%= if @redirects > 0 do %>
        <button
          phx-click="filter"
          phx-value-status="redirect"
          class={"px-3 py-1 border-3 border-black bg-[#ffee11] text-black shadow-[2px_2px_0_0_#aa00ee] cursor-pointer transition-all " <> if(@filter == :redirect, do: "ring-2 ring-white scale-110", else: "hover:scale-105")}
        >
          {@redirects} wandered off
        </button>
      <% end %>
      <%= if @errors > 0 do %>
        <button
          phx-click="filter"
          phx-value-status="error"
          class={"px-3 py-1 border-3 border-black bg-[#0088ff] text-white shadow-[2px_2px_0_0_#f11cac] cursor-pointer transition-all " <> if(@filter == :error, do: "ring-2 ring-white scale-110", else: "hover:scale-105")}
        >
          {@errors} mystery holes
        </button>
      <% end %>
    </div>
    """
  end

  defp valid_url?(url) do
    url = if String.starts_with?(url, "http"), do: url, else: "https://#{url}"
    uri = URI.parse(url)
    uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host =~ "."
  end
end
