defmodule CardsOneWeb.SearchLive do
  use CardsOneWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Search")
     |> assign(:form, to_form(%{"query" => ""}, as: :search))
     |> assign(query: "", searched?: false, search_error?: false, total: 0, page: 1, pages: 1)
     |> stream(:results, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = if is_binary(params["q"]), do: String.trim(params["q"]), else: ""
    page = parse_page(params["page"])

    socket =
      socket
      |> clear_flash()
      |> assign(:form, to_form(%{"query" => query}, as: :search))
      |> assign(query: query, searched?: query != "", search_error?: false)

    case CardsOne.Cards.search_cards(query, page) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(total: result.total, page: result.page, pages: result.pages)
         |> stream(:results, result.results, reset: true)}

      {:error, message} ->
        {:noreply,
         socket
         |> assign(search_error?: true, total: 0, page: 1, pages: 1)
         |> put_flash(:error, message)
         |> stream(:results, [], reset: true)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>Search</.header>

      <.form for={@form} id="search-form" phx-submit="search" class="space-y-4">
        <.input
          field={@form[:query]}
          id="search-query"
          type="search"
          label="Search cards and documents"
          placeholder="Enter a search term"
          class="w-full rounded-lg border border-base-300 bg-base-100 px-3 py-2 text-base-content outline-none transition-colors placeholder:text-base-content/50 focus:border-base-content/50 focus:ring-2 focus:ring-base-content/10"
        />
        <.button id="submit-search" phx-disable-with="Searching...">
          Search
        </.button>
      </.form>

      <p
        :if={@searched? && !@search_error?}
        id="search-summary"
        role="status"
        class="pt-4 text-sm text-base-content/60"
      >
        {@total} {if @total == 1, do: "result", else: "results"}
      </p>
      <p
        :if={@searched? && !@search_error? && @total == 0}
        id="search-empty"
        class="text-base-content/70"
      >
        No matching cards.
      </p>

      <div id="search-results" phx-update="stream" class="space-y-3">
        <article
          :for={{id, result} <- @streams.results}
          id={id}
          class="rounded-xl border border-base-300 p-5"
        >
          <.link
            id={"search-result-link-#{result.id}"}
            navigate={~p"/cards/#{result.filename}"}
            class="font-mono text-sm font-semibold transition-opacity hover:opacity-70 hover:underline"
          >
            {result.filename}
          </.link>
          <p class="mt-3 whitespace-pre-wrap break-words text-sm leading-6 text-base-content/70">
            {result.excerpt}
          </p>
        </article>
      </div>

      <nav
        :if={@pages > 1}
        id="search-pagination"
        aria-label="Search results pages"
        class="flex items-center justify-between gap-4 pt-4 text-sm"
      >
        <.link
          :if={@page > 1}
          id="search-previous"
          patch={~p"/search?#{%{q: @query, page: @page - 1}}"}
          class="hover:underline"
        >
          Previous
        </.link>
        <span id="search-page">Page {@page} of {@pages}</span>
        <.link
          :if={@page < @pages}
          id="search-next"
          patch={~p"/search?#{%{q: @query, page: @page + 1}}"}
          class="hover:underline"
        >
          Next
        </.link>
      </nav>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    query = String.trim(query)
    path = if query == "", do: ~p"/search", else: ~p"/search?#{%{q: query}}"
    {:noreply, push_patch(socket, to: path)}
  end

  defp parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {number, ""} when number > 0 -> number
      _ -> 1
    end
  end

  defp parse_page(_page), do: 1
end
