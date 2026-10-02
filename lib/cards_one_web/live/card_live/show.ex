defmodule CardsOneWeb.CardLive.Show do
  use CardsOneWeb, :live_view

  alias CardsOne.Cards

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Card {@card.id}
        <:subtitle>This is a card record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/cards"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/cards/#{@card}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit card
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Filename">{@card.filename}</:item>
        <:item title="Body">{@card.body}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Show Card")
     |> assign(:card, Cards.get_card!(id))}
  end
end
