defmodule CardsOne.CardsSearchTest do
  use CardsOne.DataCase

  alias CardsOne.Cards
  alias CardsOne.Cards.CardRecord
  import CardsOne.CardsFixtures

  setup do
    catalogue_fixture()
  end

  test "searches card bodies, normalizes case and accents, and returns excerpts" do
    card = card_fixture(%{body: "A café note about Phoenix and Tauri."})
    card_fixture(%{body: "Unrelated content"})

    assert {:ok, %{total: 1, results: [result]}} = Cards.search_cards("CAFE phoenix")
    assert result.filename == card.filename
    assert result.excerpt =~ "café"
    assert {:ok, %{total: 1}} = Cards.search_cards(~s(filename:"#{card.filename}"))
  end

  test "supports native phrase, prefix, boolean, proximity and column queries" do
    fox = card_fixture(%{body: "Quick brown fox jumps over the dog"})
    cat = card_fixture(%{body: "A brown cat sleeps"})

    for query <- [
          ~s("brown fox"),
          "qui*",
          "NEAR(fox dog, 6)",
          "body:fox",
          "^Quick",
          "fox AND dog"
        ] do
      assert {:ok, %{results: [%{filename: filename}], total: 1}} = Cards.search_cards(query)
      assert filename == fox.filename
    end

    assert {:ok, %{total: 2}} = Cards.search_cards("fox OR cat")

    assert {:ok, %{results: [%{filename: filename}], total: 1}} =
             Cards.search_cards("(fox OR cat) NOT dog")

    assert filename == cat.filename
  end

  test "create, update and delete keep full text results current" do
    card = card_fixture(%{body: "Beforeword"})
    assert {:ok, %{total: 1}} = Cards.search_cards("Beforeword")

    assert {:ok, updated} = Cards.update_card(card, %{body: "Afterword"})
    assert {:ok, %{total: 0}} = Cards.search_cards("Beforeword")
    assert {:ok, %{total: 1}} = Cards.search_cards("Afterword")

    assert {:ok, _} = Cards.delete_card(updated)
    assert {:ok, %{total: 0, results: []}} = Cards.search_cards("Afterword")
  end

  test "search reconciles files changed outside the app", %{directory: directory} do
    path = Path.join(directory, "external.md")
    File.write!(path, "Outsideword")
    assert {:ok, %{total: 1}} = Cards.search_cards("Outsideword")

    File.write!(path, "Revisedword")
    assert {:ok, %{total: 0}} = Cards.search_cards("Outsideword")
    assert {:ok, %{total: 1}} = Cards.search_cards("Revisedword")
    File.rm!(path)
    assert {:ok, %{total: 0}} = Cards.search_cards("Revisedword")
  end

  test "empty queries and no matches return no results" do
    assert {:ok, %{total: 0, results: []}} = Cards.search_cards(" \n ")
    card_fixture(%{body: "Some note"})
    assert {:ok, %{total: 0, results: []}} = Cards.search_cards("absentword")
  end

  test "invalid queries are recoverable, and SQL text cannot alter the database" do
    card = card_fixture(%{body: "Validword"})

    for query <- [
          ~s("unterminated),
          "word AND",
          "unknowncolumn:word",
          "foo'); DROP TABLE cards;--"
        ] do
      assert {:error, message} = Cards.search_cards(query)
      assert message =~ "could not be understood"
    end

    assert Repo.aggregate(CardRecord, :count) == 1
    assert {:ok, %{results: [%{filename: filename}]}} = Cards.search_cards("Validword")
    assert filename == card.filename
  end

  test "returns the most relevant matches first" do
    relevant = card_fixture(%{body: "Needle needle needle"})
    card_fixture(%{body: "Needle " <> String.duplicate("other words ", 80)})
    assert {:ok, %{results: [first, _second]}} = Cards.search_cards("needle")
    assert first.filename == relevant.filename
  end

  test "paginates without dropping or repeating matches" do
    for _ <- 1..23, do: card_fixture(%{body: "Commonword"})

    assert {:ok, first} = Cards.search_cards("Commonword")
    assert first.total == 23
    assert first.pages == 2
    assert length(first.results) == 20
    assert {:ok, second} = Cards.search_cards("Commonword", 2)
    assert length(second.results) == 3
    assert MapSet.disjoint?(MapSet.new(first.results), MapSet.new(second.results))
    assert {:ok, %{page: 2, results: results}} = Cards.search_cards("Commonword", 999)
    assert results == second.results
  end

  test "explicit sync rebuilds the search index from the files" do
    card = card_fixture(%{body: "Recoverword"})
    record = Repo.get_by!(CardRecord, filename: card.filename)

    Repo.query!(
      "INSERT INTO cards_fts(cards_fts, rowid, filename, body) VALUES ('delete', ?, ?, ?)",
      [record.id, record.filename, record.body]
    )

    assert %{rows: [[0]]} =
             Repo.query!("SELECT count(*) FROM cards_fts WHERE cards_fts MATCH ?", ["Recoverword"])

    assert {:ok, 1} = Cards.sync_catalogue()
    assert {:ok, %{total: 1}} = Cards.search_cards("Recoverword")
  end

  test "does not return stale hits when the catalogue cannot be read", %{config_file: config_file} do
    card_fixture(%{body: "Staleword"})
    File.write!(config_file, "catalogue-directory = '/does/not/exist'\n")
    assert {:error, _} = Cards.search_cards("Staleword")
  end
end
