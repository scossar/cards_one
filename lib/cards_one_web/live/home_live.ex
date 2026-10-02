defmodule CardsOneWeb.HomeLive do
  use CardsOneWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, count: 0)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.button navigate={~p"/cards"}>Cards</.button>
    """
  end
end
