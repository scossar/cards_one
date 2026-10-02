defmodule CardsOne.Cards.Card do
  use Ecto.Schema
  import Ecto.Changeset

  schema "cards" do
    field :filename, :string
    field :body, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(card, attrs) do
    card
    |> cast(attrs, [:filename, :body])
    |> validate_required([:filename, :body])
  end
end
