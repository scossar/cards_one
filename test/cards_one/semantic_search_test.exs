defmodule CardsOne.SemanticSearchTest do
  use CardsOne.DataCase
  import CardsOne.CardsFixtures
  alias CardsOne.Cards
  alias CardsOne.Cards.CardRecord
  alias CardsOne.SemanticSearch
  alias CardsOne.SemanticSearch.Embedding

  setup do
    previous = Application.get_env(:cards_one, :embedding_provider)
    Application.put_env(:cards_one, :embedding_provider, CardsOne.EmbeddingFixture)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cards_one, :embedding_provider, previous),
        else: Application.delete_env(:cards_one, :embedding_provider)
    end)

    catalogue_fixture()
  end

  test "ranks by vectors and skips unchanged content" do
    vehicle = card_fixture(%{body: "An automobile"})
    card_fixture(%{body: "A flower"})
    assert {:ok, 2} = SemanticSearch.index_pending()
    assert {:ok, 0} = SemanticSearch.index_pending()
    assert {:ok, %{results: [first, _], pending: 0}} = Cards.semantic_search_cards("vehicle")
    assert first.filename == vehicle.filename
    assert_in_delta first.distance, 0, 0.00001
  end

  test "multiple embeddings share filename metadata but have separate IDs and one search hit" do
    card = card_fixture(%{body: "An automobile and a flower"})
    record = Repo.get_by!(CardRecord, filename: card.filename)
    {:ok, first} = CardsOne.EmbeddingFixture.embed("car")
    {:ok, second} = CardsOne.EmbeddingFixture.embed("flower")

    assert {:ok, 2} =
             SemanticSearch.replace_embeddings(record, [
               %{content: "An automobile", position: 0, vector: first},
               %{content: "a flower", position: 1, vector: second}
             ])

    embeddings = Repo.all(Embedding)
    assert length(embeddings) == 2
    assert length(Enum.uniq_by(embeddings, & &1.id)) == 2
    assert Enum.all?(embeddings, &(&1.filename == card.filename))
    assert {:ok, %{total: 1, results: [result]}} = Cards.semantic_search_cards("vehicle")
    assert_in_delta result.distance, 0, 0.00001
  end

  test "updates and deletes invalidate metadata and vectors" do
    card = card_fixture(%{body: "An automobile"})
    assert {:ok, 1} = SemanticSearch.index_pending()
    assert {:ok, updated} = Cards.update_card(card, %{body: "A flower"})
    assert Repo.aggregate(Embedding, :count) == 0
    assert %{rows: [[0]]} = Repo.query!("SELECT count(*) FROM semantic_vectors")
    assert SemanticSearch.pending_count() == 1
    assert {:ok, 1} = SemanticSearch.index_pending()
    assert {:ok, _} = Cards.delete_card(updated)
    assert Repo.aggregate(Embedding, :count) == 0
    assert %{rows: [[0]]} = Repo.query!("SELECT count(*) FROM semantic_vectors")
  end

  test "external edits and database rebuild regenerate embeddings", %{directory: directory} do
    path = Path.join(directory, "external.md")
    File.write!(path, "An automobile")
    assert {:ok, 1} = Cards.sync_catalogue()
    assert {:ok, 1} = SemanticSearch.index_pending()
    old = Repo.one!(Embedding)
    File.write!(path, "A flower")
    assert {:ok, 1} = Cards.sync_catalogue()
    assert {:ok, 1} = SemanticSearch.index_pending()
    assert Repo.one!(Embedding).content_hash != old.content_hash
    Repo.delete_all(CardRecord)
    assert {:ok, 1} = Cards.sync_catalogue()
    assert {:ok, 1} = SemanticSearch.index_pending()
    File.rm!(path)
    assert {:ok, 0} = Cards.sync_catalogue()
    assert Repo.aggregate(Embedding, :count) == 0
  end

  test "does not publish an embedding for content changed during inference" do
    card = card_fixture(%{body: "An automobile"})
    snapshot = Repo.get_by!(CardRecord, filename: card.filename)
    {:ok, vector} = CardsOne.EmbeddingFixture.embed(snapshot.body)
    assert {:ok, _} = Cards.update_card(card, %{body: "A flower"})

    assert {:ok, :obsolete} =
             SemanticSearch.replace_embeddings(snapshot, [
               %{content: snapshot.body, position: 0, vector: vector}
             ])

    assert Repo.aggregate(Embedding, :count) == 0
  end

  test "blank cards are skipped and pending work is reported" do
    card_fixture(%{body: " \n "})
    card_fixture(%{body: "An automobile"})
    assert {:ok, %{results: [], pending: 1}} = Cards.semantic_search_cards("vehicle")
    assert {:ok, 1} = SemanticSearch.index_pending()
    assert SemanticSearch.pending_count() == 0
  end

  test "replacement rolls back both metadata and vectors if a part is invalid" do
    card = card_fixture(%{body: "An automobile"})
    assert {:ok, 1} = SemanticSearch.index_pending()
    previous = Repo.one!(Embedding)
    record = Repo.get_by!(CardRecord, filename: card.filename)
    {:ok, vector} = CardsOne.EmbeddingFixture.embed("car")

    assert_raise ArgumentError, fn ->
      SemanticSearch.replace_embeddings(record, [
        %{content: "valid", position: 0, vector: vector},
        %{content: "invalid", position: 1, vector: <<0>>}
      ])
    end

    assert Repo.one!(Embedding) == previous
    assert %{rows: [[1]]} = Repo.query!("SELECT count(*) FROM semantic_vectors")
  end

  test "a different model version is reindexed rather than mixed into results" do
    card_fixture(%{body: "An automobile"})
    assert {:ok, 1} = SemanticSearch.index_pending()
    Repo.update_all(Embedding, set: [model: "old-model"])
    assert {:ok, %{results: [], pending: 1}} = Cards.semantic_search_cards("vehicle")
    assert {:ok, 1} = SemanticSearch.index_pending()
    assert Repo.one!(Embedding).model == CardsOne.EmbeddingFixture.key()
    assert %{rows: [[1]]} = Repo.query!("SELECT count(*) FROM semantic_vectors")
  end

  test "paginates files independently of the number of embeddings" do
    for _ <- 1..21, do: card_fixture(%{body: "An automobile"})
    assert {:ok, 10} = SemanticSearch.index_pending()
    assert {:ok, 10} = SemanticSearch.index_pending()
    assert {:ok, 1} = SemanticSearch.index_pending()
    assert {:ok, %{total: 21, results: first}} = Cards.semantic_search_cards("vehicle")
    assert length(first) == 20
    assert {:ok, %{page: 2, results: second}} = Cards.semantic_search_cards("vehicle", 999)
    assert length(second) == 1
    assert MapSet.disjoint?(MapSet.new(first), MapSet.new(second))
  end
end
