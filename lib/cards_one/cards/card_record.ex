defmodule CardsOne.Cards.CardRecord do
  @moduledoc "The rebuildable SQLite copy of a Markdown card."
  use Ecto.Schema

  schema "cards" do
    field :filename, :string
    field :body, :string

    timestamps(type: :utc_datetime)
  end
end
