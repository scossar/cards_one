defmodule CardsOne.Repo.Migrations.AddCardsFullTextSearch do
  use Ecto.Migration

  def up do
    execute """
    CREATE VIRTUAL TABLE cards_fts USING fts5(
      filename, body,
      content='cards', content_rowid='id',
      tokenize='unicode61 remove_diacritics 2'
    )
    """

    execute """
    CREATE TRIGGER cards_fts_insert AFTER INSERT ON cards BEGIN
      INSERT INTO cards_fts(rowid, filename, body) VALUES (new.id, new.filename, new.body);
    END
    """

    execute """
    CREATE TRIGGER cards_fts_delete AFTER DELETE ON cards BEGIN
      INSERT INTO cards_fts(cards_fts, rowid, filename, body)
      VALUES ('delete', old.id, old.filename, old.body);
    END
    """

    execute """
    CREATE TRIGGER cards_fts_update AFTER UPDATE OF filename, body ON cards
    WHEN old.filename IS NOT new.filename OR old.body IS NOT new.body BEGIN
      INSERT INTO cards_fts(cards_fts, rowid, filename, body)
      VALUES ('delete', old.id, old.filename, old.body);
      INSERT INTO cards_fts(rowid, filename, body) VALUES (new.id, new.filename, new.body);
    END
    """

    execute "INSERT INTO cards_fts(cards_fts) VALUES ('rebuild')"
  end

  def down do
    execute "DROP TRIGGER cards_fts_update"
    execute "DROP TRIGGER cards_fts_delete"
    execute "DROP TRIGGER cards_fts_insert"
    execute "DROP TABLE cards_fts"
  end
end
