defmodule CardsOne.SemanticSearch.Embedding do
  use Ecto.Schema

  schema "semantic_embeddings" do
    field :card_id, :integer
    field :filename, :string
    field :content_hash, :string
    field :model, :string
    field :position, :integer
    field :content, :string
    timestamps(type: :utc_datetime)
  end
end
