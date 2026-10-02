defmodule CardsOne.SemanticSearch do
  @moduledoc "Rebuildable semantic projections with independent IDs and filename metadata."

  import Ecto.Query
  alias CardsOne.Cards.CardRecord
  alias CardsOne.Repo
  alias CardsOne.SemanticSearch.Embedding

  def provider,
    do: Application.get_env(:cards_one, :embedding_provider, CardsOne.SemanticSearch.Model)

  def content_hash(body), do: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

  def pending_count do
    Repo.aggregate(pending_query(), :count)
  end

  defp pending_query do
    model = provider().key()

    from card in CardRecord,
      left_join: embedding in Embedding,
      on: embedding.card_id == card.id and embedding.model == ^model,
      where:
        is_nil(embedding.id) and
          fragment("trim(?, char(9) || char(10) || char(13) || ' ') != ''", card.body)
  end

  @doc "Processes a bounded batch; unchanged cards are skipped and obsolete results discarded."
  def index_pending do
    cards = Repo.all(from card in pending_query(), order_by: card.id, limit: 10, select: card)

    Enum.reduce_while(cards, {:ok, 0}, fn card, {:ok, count} ->
      case provider().embed(card.body) do
        {:ok, vector} ->
          case replace_embeddings(card, [%{content: card.body, position: 0, vector: vector}]) do
            {:ok, _} -> {:cont, {:ok, count + 1}}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        error ->
          {:halt, error}
      end
    end)
  rescue
    error -> {:error, Exception.message(error)}
  end

  @doc "Atomically replaces a file's embeddings, accepting multiple independently identified parts."
  def replace_embeddings(card, parts) do
    Repo.transact(fn ->
      case Repo.get(CardRecord, card.id) do
        %{body: body, filename: filename} when body == card.body and filename == card.filename ->
          Repo.delete_all(from embedding in Embedding, where: embedding.card_id == ^card.id)

          Enum.each(parts, fn part ->
            unless byte_size(part.vector) == 384 * 4 do
              raise ArgumentError, "Expected a 384-dimensional float32 embedding"
            end

            embedding =
              Repo.insert!(%Embedding{
                card_id: card.id,
                filename: card.filename,
                model: provider().key(),
                content_hash: content_hash(card.body),
                content: part.content,
                position: part.position
              })

            Repo.query!(
              "INSERT INTO semantic_vectors(rowid, embedding) VALUES (?, CAST(? AS BLOB))",
              [
                embedding.id,
                part.vector
              ]
            )
          end)

          {:ok, length(parts)}

        _ ->
          {:ok, :obsolete}
      end
    end)
  end

  def search(query, page \\ 1) do
    with {:ok, vector} <- provider().embed(query) do
      Repo.transact(fn ->
        %{rows: [[total]]} =
          Repo.query!(
            "SELECT count(DISTINCT card_id) FROM semantic_embeddings WHERE model = ?",
            [provider().key()]
          )

        pages = max(div(total + 19, 20), 1)
        page = min(max(page, 1), pages)
        # Group by source file: several matching parts must not duplicate a card.
        # Scalar cosine distance allows all matching files to be paginated consistently.
        %{rows: rows} =
          Repo.query!(
            """
            SELECT cards.id, cards.filename, cards.body,
                   MIN(vec_distance_cosine(vectors.embedding, CAST(? AS BLOB))) AS distance
            FROM semantic_vectors AS vectors
            JOIN semantic_embeddings AS metadata ON metadata.id = vectors.rowid
            JOIN cards ON cards.id = metadata.card_id
            WHERE metadata.model = ?
            GROUP BY cards.id
            ORDER BY distance, cards.filename
            LIMIT ? OFFSET ?
            """,
            [vector, provider().key(), 20, (page - 1) * 20]
          )

        results =
          rows
          |> Enum.map(fn [id, filename, body, distance] ->
            %{id: id, filename: filename, excerpt: String.slice(body, 0, 240), distance: distance}
          end)

        {:ok,
         %{results: results, total: total, page: page, pages: pages, pending: pending_count()}}
      end)
    end
  rescue
    _ -> {:error, :unavailable}
  end
end
