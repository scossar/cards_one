defmodule CardsOneWeb.CardLive.Form do
  use CardsOneWeb, :live_view

  alias CardsOne.Cards
  alias CardsOne.Cards.Card

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage card records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="card-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:filename]} type="text" label="Filename" />
        <.input field={@form[:body]} type="textarea" label="Body" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Card</.button>
          <.button navigate={return_path(@return_to, @card)}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    card = Cards.get_card!(id)

    socket
    |> assign(:page_title, "Edit Card")
    |> assign(:card, card)
    |> assign(:form, to_form(Cards.change_card(card)))
  end

  defp apply_action(socket, :new, _params) do
    card = %Card{}

    socket
    |> assign(:page_title, "New Card")
    |> assign(:card, card)
    |> assign(:form, to_form(Cards.change_card(card)))
  end

  @impl true
  def handle_event("validate", %{"card" => card_params}, socket) do
    changeset = Cards.change_card(socket.assigns.card, card_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"card" => card_params}, socket) do
    save_card(socket, socket.assigns.live_action, card_params)
  end

  defp save_card(socket, :edit, card_params) do
    case Cards.update_card(socket.assigns.card, card_params) do
      {:ok, card} ->
        {:noreply,
         socket
         |> put_flash(:info, "Card updated successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, card))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_card(socket, :new, card_params) do
    case Cards.create_card(card_params) do
      {:ok, card} ->
        {:noreply,
         socket
         |> put_flash(:info, "Card created successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, card))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("index", _card), do: ~p"/cards"
  defp return_path("show", card), do: ~p"/cards/#{card}"
end
