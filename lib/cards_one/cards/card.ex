defmodule CardsOne.Cards.Card do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  embedded_schema do
    field :filename, :string
    field :body, :string, default: ""
    field :catalogue_directory, :string
  end

  @doc false
  def changeset(card, attrs) do
    changeset = cast(card, attrs, [:body], empty_values: [])

    body = get_field(changeset, :body)

    if is_binary(body) and String.valid?(body) do
      changeset
    else
      add_error(changeset, :body, "must be UTF-8 Markdown text")
    end
  end
end
