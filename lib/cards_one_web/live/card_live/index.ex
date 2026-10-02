defmodule CardsOneWeb.CardLive.Index do
  use CardsOneWeb, :live_view

  alias CardsOne.Cards

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Cards
        <:actions>
          <.button id="new-card" variant="primary" navigate={~p"/cards/new"}>
            <.icon name="hero-plus" /> New Card
          </.button>
        </:actions>
      </.header>

      <div id="cards" phx-update="stream" class="space-y-3">
        <p
          id="cards-empty"
          class="hidden only:block rounded-xl border border-base-300 p-6 text-base-content/60"
        >
          No cards yet. Create your first note.
        </p>
        <article
          :for={{id, card} <- @streams.cards}
          id={id}
          class="rounded-xl border border-base-300 p-5 transition-colors hover:border-base-content/30"
        >
          <.link
            id={"show-#{card.filename}"}
            navigate={~p"/cards/#{card}"}
            class="font-mono text-sm font-semibold hover:underline"
          >
            {card.filename}
          </.link>
          <p class="mt-3 whitespace-pre-wrap break-words text-sm text-base-content/70">
            {String.slice(card.body, 0, 180)}
          </p>
          <div class="mt-4 flex gap-4 text-sm">
            <.link
              id={"edit-#{card.filename}"}
              navigate={~p"/cards/#{card}/edit"}
              class="hover:underline"
            >Edit</.link>
            <button
              id={"delete-#{card.filename}"}
              type="button"
              phx-click="delete"
              phx-value-id={card.filename}
              data-confirm="Delete this card file?"
              class="cursor-pointer text-red-600 transition-colors hover:text-red-700"
            >
              Delete
            </button>
          </div>
        </article>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, :page_title, "Cards")

    socket =
      case Cards.list_cards() do
        {:ok, cards} -> stream(socket, :cards, cards)
        {:ok, cards, warning} -> socket |> put_flash(:error, warning) |> stream(:cards, cards)
        {:error, message} -> socket |> put_flash(:error, message) |> stream(:cards, [])
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => filename}, socket) do
    with {:ok, card} <- Cards.get_card(filename) do
      case Cards.delete_card(card) do
        {:ok, deleted} ->
          {:noreply,
           socket
           |> stream_delete(:cards, deleted)
           |> put_flash(:info, "Card deleted successfully")}

        {:ok, deleted, warning} ->
          {:noreply, socket |> stream_delete(:cards, deleted) |> put_flash(:error, warning)}

        {:error, message} ->
          {:noreply, put_flash(socket, :error, message)}
      end
    else
      {:error, message} -> {:noreply, put_flash(socket, :error, message)}
    end
  end
end
