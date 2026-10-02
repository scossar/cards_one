defmodule CardsOne.Cards.Database do
  @moduledoc false

  import Ecto.Query
  alias CardsOne.Cards.CardRecord
  alias CardsOne.Repo

  def reconcile(cards, opts \\ []) do
    database_operation(fn ->
      Repo.transact(fn ->
        upsert_cards(cards)
        filenames = Enum.map(cards, & &1.filename)

        stale =
          if filenames == [] do
            CardRecord
          else
            from record in CardRecord,
              where: is_nil(record.filename) or record.filename not in ^filenames
          end

        Repo.delete_all(stale)

        if opts[:rebuild_search?] do
          Repo.query!("INSERT INTO cards_fts(cards_fts) VALUES ('rebuild')")
        end

        {:ok, length(cards)}
      end)
    end)
  end

  def search(query, page) do
    result =
      database_operation(fn ->
        Repo.transact(fn ->
          %{rows: [[total]]} =
            Repo.query!("SELECT count(*) FROM cards_fts WHERE cards_fts MATCH ?", [query])

          page_size = 20
          pages = max(div(total + page_size - 1, page_size), 1)
          page = min(page, pages)

          %{rows: rows} =
            Repo.query!(
              """
              SELECT cards.id, cards.filename, snippet(cards_fts, 1, '', '', ' … ', 32)
              FROM cards_fts JOIN cards ON cards.id = cards_fts.rowid
              WHERE cards_fts MATCH ?
              ORDER BY bm25(cards_fts, 2.0, 1.0), cards.filename
              LIMIT ? OFFSET ?
              """,
              [query, page_size, (page - 1) * page_size]
            )

          results =
            Enum.map(rows, fn [id, filename, excerpt] ->
              %{id: id, filename: filename, excerpt: excerpt}
            end)

          {:ok, %{results: results, total: total, page: page, pages: pages}}
        end)
      end)

    case result do
      {:error, reason} ->
        if String.contains?(reason, [
             "fts5: syntax error",
             "unterminated string",
             "no such column:"
           ]) do
          {:error, :invalid_query}
        else
          {:error, :unavailable}
        end

      result ->
        result
    end
  end

  def put(card) do
    database_operation(fn ->
      upsert_cards([card])
      :ok
    end)
  end

  def delete(filename) do
    database_operation(fn ->
      Repo.delete_all(from record in CardRecord, where: record.filename == ^filename)
      :ok
    end)
  end

  defp upsert_cards(cards) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    cards
    |> Enum.map(fn card ->
      %{filename: card.filename, body: card.body, inserted_at: now, updated_at: now}
    end)
    |> Enum.chunk_every(100)
    |> Enum.each(fn entries ->
      Repo.insert_all(CardRecord, entries,
        conflict_target: [:filename],
        on_conflict: {:replace, [:body, :updated_at]}
      )
    end)
  end

  defp database_operation(operation) do
    operation.()
  rescue
    error in [Exqlite.Error, DBConnection.ConnectionError, Ecto.ConstraintError, Ecto.QueryError] ->
      {:error, Exception.message(error)}
  end
end
