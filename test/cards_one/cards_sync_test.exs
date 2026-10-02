defmodule CardsOne.CardsSyncTest do
  use CardsOne.DataCase

  alias CardsOne.Cards
  alias CardsOne.Cards.CardRecord
  import CardsOne.CardsFixtures

  setup do
    catalogue_fixture()
  end

  test "a destroyed SQLite file can be recreated entirely from the catalogue", %{
    root: root,
    directory: directory
  } do
    File.write!(Path.join(directory, "first.md"), "# First card\n")
    File.write!(Path.join(directory, "second.md"), "# Second card\n")
    database = Path.join(root, "rebuild.sqlite3")

    migrations =
      Path.wildcard("priv/repo/migrations/*.exs")
      |> Enum.map(fn path ->
        {version, _} = Integer.parse(Path.basename(path))
        [{module, _binary}] = Code.compile_file(path)
        {version, module}
      end)

    options = [
      database: database,
      name: nil,
      pool: DBConnection.ConnectionPool,
      pool_size: 1,
      journal_mode: :delete
    ]

    pid = start_supervised!({Repo, options})
    previous = Repo.put_dynamic_repo(pid)

    try do
      Ecto.Migrator.run(Repo, migrations, :up, all: true, log: false)
      assert {:ok, 2} = Cards.sync_catalogue()
      assert Repo.aggregate(CardRecord, :count) == 2

      stop_supervised!(Repo)
      File.rm!(database)
      refute File.exists?(database)

      recreated = start_supervised!({Repo, options})
      Repo.put_dynamic_repo(recreated)
      Ecto.Migrator.run(Repo, migrations, :up, all: true, log: false)
      assert Repo.all(CardRecord) == []
      assert {:ok, 2} = Cards.sync_catalogue()

      assert Repo.all(
               from record in CardRecord,
                 order_by: record.filename,
                 select: {record.filename, record.body}
             ) ==
               [{"first.md", "# First card\n"}, {"second.md", "# Second card\n"}]
    after
      Repo.put_dynamic_repo(previous)
    end
  end

  test "imports files into an empty database and repeated syncs keep unique rows", %{
    directory: directory
  } do
    File.write!(Path.join(directory, "1790921230.md"), "# First\n")
    File.write!(Path.join(directory, "1790921231.md"), "# Second\n")

    assert {:ok, 2} = Cards.sync_catalogue()
    original = Repo.all(from record in CardRecord, order_by: record.filename)

    assert Enum.map(original, &{&1.filename, &1.body}) == [
             {"1790921230.md", "# First\n"},
             {"1790921231.md", "# Second\n"}
           ]

    assert {:ok, 2} = Cards.sync_catalogue()

    assert Enum.map(Repo.all(from record in CardRecord, order_by: record.filename), & &1.id) ==
             Enum.map(original, & &1.id)

    # Losing the index must not lose any card content.
    Repo.delete_all(CardRecord)
    assert {:ok, 2} = Cards.sync_catalogue()
    assert Repo.aggregate(CardRecord, :count) == 2
    assert Repo.get_by!(CardRecord, filename: "1790921230.md").body == "# First\n"
    assert File.read!(Path.join(directory, "1790921231.md")) == "# Second\n"
  end

  test "listing reconciles external edits, additions and deletions", %{directory: directory} do
    first = card_fixture(%{body: "Old body"})
    removed = card_fixture()
    File.write!(Path.join(directory, first.filename), "External edit")
    File.rm!(Path.join(directory, removed.filename))
    File.write!(Path.join(directory, "imported.md"), "External creation")

    assert {:ok, cards} = Cards.list_cards()
    assert length(cards) == 2
    assert Repo.get_by!(CardRecord, filename: first.filename).body == "External edit"
    assert Repo.get_by!(CardRecord, filename: "imported.md").body == "External creation"
    refute Repo.get_by(CardRecord, filename: removed.filename)
  end

  test "an empty catalogue clears stale database rows", %{directory: directory} do
    card = card_fixture()
    File.rm!(Path.join(directory, card.filename))
    assert {:ok, 0} = Cards.sync_catalogue()
    assert Repo.all(CardRecord) == []
  end

  test "invalid or unreadable files never reconcile an incomplete scan", %{
    directory: directory,
    config_file: config_file
  } do
    card = card_fixture()
    File.write!(Path.join(directory, card.filename), "Changed on disk")
    File.write!(Path.join(directory, "invalid.md"), <<255>>)

    assert {:error, _} = Cards.sync_catalogue()
    assert Repo.get_by!(CardRecord, filename: card.filename).body == card.body
    assert Repo.aggregate(CardRecord, :count) == 1

    File.rm!(Path.join(directory, "invalid.md"))
    File.chmod!(Path.join(directory, card.filename), 0o000)

    try do
      assert {:error, _} = Cards.sync_catalogue()
      assert Repo.get_by!(CardRecord, filename: card.filename).body == card.body
    after
      File.chmod!(Path.join(directory, card.filename), 0o644)
    end

    File.write!(config_file, "catalogue-directory = '/does/not/exist'\n")
    assert {:error, _} = Cards.sync_catalogue()
    assert Repo.aggregate(CardRecord, :count) == 1
  end

  test "switching catalogues replaces the index with the new source", %{
    root: root,
    config_file: config_file
  } do
    old = card_fixture()
    other = Path.join(root, "other")
    File.mkdir!(other)
    File.write!(Path.join(other, "new.md"), "Other catalogue")
    File.write!(config_file, "catalogue-directory = '#{other}'\n")

    assert {:ok, 1} = Cards.sync_catalogue()
    assert [%{filename: "new.md", body: "Other catalogue"}] = Repo.all(CardRecord)
    assert File.exists?(Path.join(old.catalogue_directory, old.filename))
  end

  test "SQLite enforces unique filenames" do
    card = card_fixture()
    duplicate = %CardRecord{filename: card.filename, body: "Duplicate"}

    changeset =
      duplicate |> Ecto.Changeset.change() |> Ecto.Changeset.unique_constraint(:filename)

    assert {:error, changeset} = Repo.insert(changeset)
    assert {"has already been taken", _} = Keyword.fetch!(changeset.errors, :filename)
    assert Repo.aggregate(CardRecord, :count) == 1
  end

  test "database failures preserve filesystem changes and a later sync repairs the copies", %{
    directory: directory
  } do
    updated = card_fixture(%{body: "Before"})
    deleted = card_fixture()
    block_inserts()
    block_deletes()

    assert {:ok, created, warning} = Cards.create_card(%{body: "New card"})
    assert warning =~ "saved to disk"
    assert File.read!(Path.join(directory, created.filename)) == "New card"
    refute Repo.get_by(CardRecord, filename: created.filename)

    assert {:ok, changed, warning} = Cards.update_card(updated, %{body: "After"})
    assert warning =~ "database copy"
    assert File.read!(Path.join(directory, changed.filename)) == "After"
    assert Repo.get_by!(CardRecord, filename: changed.filename).body == "Before"

    assert {:ok, _, warning} = Cards.delete_card(deleted)
    assert warning =~ "file deleted"
    refute File.exists?(Path.join(directory, deleted.filename))
    assert Repo.get_by(CardRecord, filename: deleted.filename)

    assert {:ok, cards, warning} = Cards.list_cards()
    assert length(cards) == 2
    assert warning =~ "loaded from disk"

    Ecto.Adapters.SQL.query!(Repo, "DROP TRIGGER block_card_inserts")
    Ecto.Adapters.SQL.query!(Repo, "DROP TRIGGER block_card_deletes")
    assert {:ok, 2} = Cards.sync_catalogue()
    assert Repo.get_by!(CardRecord, filename: created.filename).body == "New card"
    assert Repo.get_by!(CardRecord, filename: changed.filename).body == "After"
    refute Repo.get_by(CardRecord, filename: deleted.filename)
  end

  test "reconciliation rolls back all database changes when a later step fails", %{
    directory: directory
  } do
    kept = card_fixture(%{body: "Original"})
    stale = card_fixture()
    File.write!(Path.join(directory, kept.filename), "Changed")
    File.rm!(Path.join(directory, stale.filename))
    File.write!(Path.join(directory, "new.md"), "New")
    block_deletes()

    assert {:error, _} = Cards.sync_catalogue()
    assert Repo.get_by!(CardRecord, filename: kept.filename).body == "Original"
    assert Repo.get_by(CardRecord, filename: stale.filename)
    refute Repo.get_by(CardRecord, filename: "new.md")
  end

  defp block_inserts do
    Ecto.Adapters.SQL.query!(Repo, """
    CREATE TRIGGER block_card_inserts BEFORE INSERT ON cards
    BEGIN SELECT RAISE(ABORT, 'test database write failure'); END
    """)
  end

  defp block_deletes do
    Ecto.Adapters.SQL.query!(Repo, """
    CREATE TRIGGER block_card_deletes BEFORE DELETE ON cards
    BEGIN SELECT RAISE(ABORT, 'test database delete failure'); END
    """)
  end
end
