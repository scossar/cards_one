defmodule CardsOneWeb.CardLive.Index do
  use CardsOneWeb, :live_view

  alias CardsOne.Cards

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Cards
        <:actions>
          <.button variant="primary" navigate={~p"/cards/new"}>
            <.icon name="hero-plus" /> New Card
          </.button>
        </:actions>
      </.header>

      <.table
        id="cards"
        rows={@streams.cards}
        row_click={fn {_id, card} -> JS.navigate(~p"/cards/#{card}") end}
      >
        <:col :let={{_id, card}} label="Filename">{card.filename}</:col>
        <:col :let={{_id, card}} label="Body">{card.body}</:col>
        <:action :let={{_id, card}}>
          <div class="sr-only">
            <.link navigate={~p"/cards/#{card}"}>Show</.link>
          </div>
          <.link navigate={~p"/cards/#{card}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, card}}>
          <.link
            phx-click={JS.push("delete", value: %{id: card.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Cards")
     |> stream(:cards, list_cards())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    card = Cards.get_card!(id)
    {:ok, _} = Cards.delete_card(card)

    {:noreply, stream_delete(socket, :cards, card)}
  end

  defp list_cards() do
    Cards.list_cards()
  end
end
