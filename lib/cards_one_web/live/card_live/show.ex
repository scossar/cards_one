defmodule CardsOneWeb.CardLive.Show do
  use CardsOneWeb, :live_view

  alias CardsOne.Cards

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        <span id="card-title" class="font-mono">{@card.filename}</span>
        <:actions>
          <.button id="back-to-cards" navigate={~p"/cards"}>
            <.icon name="hero-arrow-left" /> Cards
          </.button>
          <.button id="edit-card" variant="primary" navigate={~p"/cards/#{@card}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit card
          </.button>
        </:actions>
      </.header>

      <pre
        id="card-body"
        class="whitespace-pre-wrap break-words rounded-xl border border-base-300 p-6 font-mono text-sm leading-7"
      >{@card.body}</pre>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => filename}, _session, socket) do
    case Cards.get_card(filename) do
      {:ok, card} ->
        {:ok, socket |> assign(:page_title, card.filename) |> assign(:card, card)}

      {:error, message} ->
        {:ok, socket |> put_flash(:error, message) |> push_navigate(to: ~p"/cards")}
    end
  end
end
