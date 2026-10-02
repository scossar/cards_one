defmodule CardsOneWeb.SearchLive do
  use CardsOneWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Search")
     |> assign(:form, to_form(%{"query" => ""}, as: :search))
     |> assign(
       query: "",
       mode: "text",
       loading?: false,
       pending: 0,
       searched?: false,
       search_error?: false,
       total: 0,
       page: 1,
       pages: 1
     )
     |> stream(:results, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = if is_binary(params["q"]), do: String.trim(params["q"]), else: ""
    page = parse_page(params["page"])
    mode = if params["mode"] == "semantic", do: "semantic", else: "text"

    socket =
      socket
      |> clear_flash()
      |> cancel_async(:semantic_search)
      |> assign(:form, to_form(%{"query" => query, "mode" => mode}, as: :search))
      |> assign(
        query: query,
        mode: mode,
        loading?: false,
        pending: 0,
        searched?: query != "",
        search_error?: false
      )

    if mode == "semantic" and query != "" do
      {:noreply,
       socket
       |> assign(loading?: true, total: 0, page: 1, pages: 1)
       |> stream(:results, [], reset: true)
       |> start_async(:semantic_search, fn ->
         CardsOne.Cards.semantic_search_cards(query, page)
       end)}
    else
      {:noreply, apply_result(socket, CardsOne.Cards.search_cards(query, page))}
    end
  end

  @impl true
  def handle_async(:semantic_search, {:ok, result}, socket) do
    {:noreply, apply_result(assign(socket, loading?: false), result)}
  end

  def handle_async(:semantic_search, {:exit, _reason}, socket) do
    {:noreply,
     apply_result(
       assign(socket, loading?: false),
       {:error, "Semantic search is temporarily unavailable."}
     )}
  end

  defp apply_result(socket, result) do
    case result do
      {:ok, result} ->
        socket
        |> assign(
          total: result.total,
          page: result.page,
          pages: result.pages,
          pending: Map.get(result, :pending, 0)
        )
        |> stream(:results, result.results, reset: true)

      {:error, message} ->
        socket
        |> assign(search_error?: true, total: 0, page: 1, pages: 1)
        |> put_flash(:error, message)
        |> stream(:results, [], reset: true)
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
        <.input
          field={@form[:mode]}
          id="search-mode"
          type="select"
          label="Search type"
          options={[{"Text", "text"}, {"Semantic", "semantic"}]}
        />
        <.button id="submit-search" phx-disable-with="Searching...">
          Search
        </.button>
      </.form>

      <p :if={@mode == "semantic"} id="search-semantic-note" class="pt-4 text-sm text-base-content/60">
        Semantic search currently considers the beginning of each card.
      </p>

      <p :if={@loading?} id="search-loading" role="status" class="pt-4 text-sm text-base-content/60">
        Searching…
      </p>
      <p
        :if={@mode == "semantic" && @pending > 0}
        id="search-indexing"
        role="status"
        class="pt-4 text-sm text-base-content/60"
      >
        {@pending} {if @pending == 1, do: "card is", else: "cards are"} still being indexed. Search again shortly for updated results.
      </p>

      <p
        :if={@searched? && !@search_error? && !@loading?}
        id="search-summary"
        role="status"
        class="pt-4 text-sm text-base-content/60"
      >
        {@total} {if @total == 1, do: "result", else: "results"}
      </p>
      <p
        :if={@searched? && !@search_error? && !@loading? && @total == 0}
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
          patch={search_path(@query, @mode, @page - 1)}
          class="hover:underline"
        >
          Previous
        </.link>
        <span id="search-page">Page {@page} of {@pages}</span>
        <.link
          :if={@page < @pages}
          id="search-next"
          patch={search_path(@query, @mode, @page + 1)}
          class="hover:underline"
        >
          Next
        </.link>
      </nav>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query} = params}, socket) do
    query = String.trim(query)
    mode = if params["mode"] == "semantic", do: "semantic", else: "text"
    path = search_path(query, mode, 1)
    {:noreply, push_patch(socket, to: path)}
  end

  defp search_path(query, mode, page) do
    params = if query == "", do: %{}, else: %{q: query}
    params = if mode == "semantic", do: Map.put(params, :mode, mode), else: params
    params = if page > 1, do: Map.put(params, :page, page), else: params
    if params == %{}, do: ~p"/search", else: ~p"/search?#{params}"
  end

  defp parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {number, ""} when number > 0 -> number
      _ -> 1
    end
  end

  defp parse_page(_page), do: 1
end
