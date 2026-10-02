defmodule CardsOneWeb.HomeLive do
  use CardsOneWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      case CardsOne.Config.catalogue_directory() do
        {:ok, _directory} -> socket
        {:error, notice} -> put_flash(socket, :info, notice)
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.button id="open-cards" navigate={~p"/cards"}>Cards</.button>
    </Layouts.app>
    """
  end
end
