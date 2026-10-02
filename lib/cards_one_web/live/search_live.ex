defmodule CardsOneWeb.SearchLive do
  use CardsOneWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Search")
     |> assign(:form, to_form(%{"query" => ""}, as: :search))}
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
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("search", %{"search" => params}, socket) do
    {:noreply,
     socket
     |> assign(:form, to_form(params, as: :search))
     |> put_flash(:info, "Search is not available yet.")}
  end
end
