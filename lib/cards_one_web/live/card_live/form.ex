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
        <:subtitle>
          <span :if={@card.filename} class="font-mono">{@card.filename}</span>
          <span :if={!@card.filename}>A timestamp filename will be generated when you save.</span>
        </:subtitle>
      </.header>

      <.form for={@form} id="card-form" phx-change="validate" phx-submit="save">
        <.input
          field={@form[:body]}
          type="textarea"
          label="Markdown"
          rows="16"
          class="w-full resize-y rounded-xl border border-base-300 bg-base-100 p-4 font-mono text-sm leading-7 outline-none transition-colors focus:border-base-content/50 focus:ring-2 focus:ring-base-content/10"
        />
        <footer class="mt-5 flex gap-3">
          <.button id="save-card" phx-disable-with="Saving..." variant="primary">Save Card</.button>
          <.button id="cancel-card" navigate={return_path(@return_to, @card)}>Cancel</.button>
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
    case Cards.get_card(id) do
      {:ok, card} ->
        socket
        |> assign(:page_title, "Edit Card")
        |> assign(:card, card)
        |> assign(:form, to_form(Cards.change_card(card)))

      {:error, message} ->
        socket |> put_flash(:error, message) |> push_navigate(to: ~p"/cards")
    end
  end

  defp apply_action(socket, :new, _params) do
    case CardsOne.Config.catalogue_directory() do
      {:ok, _directory} ->
        card = %Card{}

        socket
        |> assign(:page_title, "New Card")
        |> assign(:card, card)
        |> assign(:form, to_form(Cards.change_card(card)))

      {:error, message} ->
        socket |> put_flash(:error, message) |> push_navigate(to: ~p"/")
    end
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

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
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

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  defp return_path("index", _card), do: ~p"/cards"
  defp return_path("show", card), do: ~p"/cards/#{card}"
end
