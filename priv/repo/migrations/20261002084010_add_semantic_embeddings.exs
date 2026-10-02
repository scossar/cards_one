defmodule CardsOne.Repo.Migrations.AddSemanticEmbeddings do
  use Ecto.Migration

  def up do
    create table(:semantic_embeddings) do
      add :card_id, references(:cards, on_delete: :delete_all), null: false
      add :filename, :text, null: false
      add :content_hash, :string, null: false
      add :model, :text, null: false
      add :position, :integer, null: false
      add :content, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:semantic_embeddings, [:card_id])
    create index(:semantic_embeddings, [:filename])

    execute "CREATE VIRTUAL TABLE semantic_vectors USING vec0(embedding float[384] distance_metric=cosine)"

    execute """
    CREATE TRIGGER semantic_embeddings_delete AFTER DELETE ON semantic_embeddings BEGIN
      DELETE FROM semantic_vectors WHERE rowid = old.id;
    END
    """

    execute """
    CREATE TRIGGER cards_semantic_update AFTER UPDATE ON cards
    WHEN old.body IS NOT new.body OR old.filename IS NOT new.filename BEGIN
      DELETE FROM semantic_embeddings WHERE card_id = old.id;
    END
    """
  end

  def down do
    execute "DROP TRIGGER cards_semantic_update"
    execute "DROP TRIGGER semantic_embeddings_delete"
    execute "DROP TABLE semantic_vectors"
    drop table(:semantic_embeddings)
  end
end
