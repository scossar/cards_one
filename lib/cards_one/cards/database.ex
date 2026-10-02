defmodule CardsOne.Cards.Database do
  @moduledoc false

  import Ecto.Query
  alias CardsOne.Cards.CardRecord
  alias CardsOne.Repo

  def reconcile(cards) do
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
        {:ok, length(cards)}
      end)
    end)
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
