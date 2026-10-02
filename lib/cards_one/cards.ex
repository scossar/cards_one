defmodule CardsOne.Cards do
  @moduledoc """
  Filesystem-backed Markdown cards. The configured catalogue is the source of truth.
  """

  alias CardsOne.Cards.Card
  alias CardsOne.Cards.Database
  alias CardsOne.Config

  def list_cards do
    with_catalogue_lock(fn ->
      with {:ok, cards} <- read_catalogue() do
        case Database.reconcile(cards) do
          {:ok, _count} -> {:ok, cards}
          {:error, _reason} -> {:ok, cards, database_warning("Cards loaded from disk")}
        end
      end
    end)
  end

  @doc "Rebuilds the SQLite copy from all files in the configured catalogue."
  def sync_catalogue do
    with_catalogue_lock(fn ->
      with {:ok, cards} <- read_catalogue() do
        Database.reconcile(cards, rebuild_search?: true)
      end
    end)
  end

  @doc "Searches the current catalogue using the full SQLite FTS5 query syntax."
  def search_cards(query, page \\ 1) when is_binary(query) and is_integer(page) and page > 0 do
    query = String.trim(query)

    if query == "" do
      {:ok, %{results: [], total: 0, page: 1, pages: 1}}
    else
      with_catalogue_lock(fn ->
        with {:ok, cards} <- read_catalogue(),
             {:ok, _count} <- reconcile_for_search(cards) do
          case Database.search(query, page) do
            {:error, :invalid_query} ->
              {:error, "This search could not be understood. Check your query and try again."}

            {:error, :unavailable} ->
              {:error, "Search is temporarily unavailable. Please try again."}

            result ->
              result
          end
        else
          {:error, reason} -> {:error, reason}
        end
      end)
    end
  end

  defp reconcile_for_search(cards) do
    case Database.reconcile(cards) do
      {:ok, count} -> {:ok, count}
      {:error, _reason} -> {:error, "Search is temporarily unavailable. Please try again."}
    end
  end

  @doc "Searches file content by meaning using the local embedding model."
  def semantic_search_cards(query, page \\ 1) do
    query = String.trim(query)

    if query == "" do
      {:ok, %{results: [], total: 0, page: 1, pages: 1, pending: 0}}
    else
      with {:ok, _cards} <- normalize_catalogue_result(list_cards()) do
        case CardsOne.SemanticSearch.search(query, page) do
          {:error, :loading} ->
            {:error, "Semantic search is preparing its model. Please try again shortly."}

          {:error, _} ->
            {:error,
             "Semantic search is temporarily unavailable. Text search is still available."}

          result ->
            result
        end
      end
    end
  end

  defp normalize_catalogue_result({:ok, cards}), do: {:ok, cards}

  defp normalize_catalogue_result({:ok, _cards, _warning}),
    do: {:error, "Search is temporarily unavailable. Please try again."}

  defp normalize_catalogue_result(error), do: error

  defp read_catalogue do
    with {:ok, directory} <- Config.catalogue_directory(),
         {:ok, filenames} <- file_result(File.ls(directory), "list the catalogue") do
      filenames
      |> Enum.filter(&valid_filename?/1)
      |> Enum.sort(:desc)
      |> Enum.reduce_while({:ok, []}, fn filename, {:ok, cards} ->
        path = Path.join(directory, filename)

        case File.lstat(path) do
          {:ok, %File.Stat{type: :regular}} ->
            case read_card(directory, filename) do
              {:ok, card} -> {:cont, {:ok, [card | cards]}}
              error -> {:halt, error}
            end

          {:ok, _stat} ->
            # Subdirectories and symbolic links are not catalogue cards.
            {:cont, {:ok, cards}}

          error ->
            # An incomplete scan must never remove database records.
            {:halt, file_result(error, "inspect #{filename}")}
        end
      end)
      |> case do
        {:ok, cards} -> {:ok, Enum.reverse(cards)}
        error -> error
      end
    end
  end

  def get_card(filename) do
    with {:ok, directory} <- Config.catalogue_directory(),
         :ok <- check_filename(filename),
         :ok <- check_regular_file(Path.join(directory, filename)) do
      read_card(directory, filename)
    end
  end

  def create_card(attrs) do
    with_catalogue_lock(fn ->
      with {:ok, card} <- %Card{} |> Card.changeset(attrs) |> Ecto.Changeset.apply_action(:insert),
           {:ok, directory} <- Config.catalogue_directory(),
           {:ok, saved} <- create_file(directory, card.body, :second, 10) do
        indexed_result(saved, Database.put(saved), "Card saved to disk")
      end
    end)
  end

  def update_card(%Card{} = card, attrs) do
    with_catalogue_lock(fn ->
      with {:ok, updated} <- card |> Card.changeset(attrs) |> Ecto.Changeset.apply_action(:update),
           {:ok, path} <- card_path(card),
           :ok <- check_regular_file(path),
           :ok <- replace_file(path, updated.body) do
        indexed_result(updated, Database.put(updated), "Card saved to disk")
      end
    end)
  end

  def delete_card(%Card{} = card) do
    with_catalogue_lock(fn ->
      with {:ok, path} <- card_path(card),
           :ok <- check_regular_file(path),
           :ok <- file_result(File.rm(path), "delete #{card.filename}") do
        indexed_result(card, Database.delete(card.filename), "Card file deleted")
      end
    end)
  end

  def change_card(%Card{} = card, attrs \\ %{}), do: Card.changeset(card, attrs)

  defp with_catalogue_lock(operation) do
    :global.trans({{__MODULE__, :catalogue}, self()}, operation, [node()])
  end

  defp indexed_result(card, :ok, _action), do: {:ok, card}

  defp indexed_result(card, {:error, _reason}, action) do
    {:ok, card, database_warning(action)}
  end

  defp database_warning(action) do
    "#{action}, but the database copy could not be synchronized. Reload the card list to retry."
  end

  defp create_file(_directory, _body, _unit, 0) do
    {:error, "Could not generate a unique timestamp filename. Please try again."}
  end

  defp create_file(directory, body, unit, attempts) do
    filename = "#{System.system_time(unit)}.md"

    case File.write(Path.join(directory, filename), body, [:exclusive]) do
      :ok ->
        {:ok, %Card{id: filename, filename: filename, body: body, catalogue_directory: directory}}

      {:error, :eexist} ->
        # Keep the usual seconds-based title, using microseconds for collisions.
        create_file(directory, body, :microsecond, attempts - 1)

      error ->
        file_result(error, "create #{filename}")
    end
  end

  defp replace_file(path, body) do
    temporary = Path.join(Path.dirname(path), ".cards-one-save-#{Ecto.UUID.generate()}")

    case File.write(temporary, body, [:exclusive]) do
      :ok ->
        try do
          file_result(File.rename(temporary, path), "save #{Path.basename(path)}")
        after
          File.rm(temporary)
        end

      error ->
        file_result(error, "save #{Path.basename(path)}")
    end
  end

  defp card_path(card) do
    with {:ok, directory} <- Config.catalogue_directory(),
         :ok <- check_filename(card.filename) do
      if directory == card.catalogue_directory do
        {:ok, Path.join(directory, card.filename)}
      else
        {:error, "The catalogue directory changed. Reopen the card before editing it."}
      end
    end
  end

  defp read_card(directory, filename) do
    with {:ok, body} <- file_result(File.read(Path.join(directory, filename)), "read #{filename}") do
      if String.valid?(body) do
        {:ok, %Card{id: filename, filename: filename, body: body, catalogue_directory: directory}}
      else
        {:error, "#{filename} is not valid UTF-8 text."}
      end
    end
  end

  defp valid_filename?(filename) when is_binary(filename) do
    String.valid?(filename) && String.ends_with?(filename, ".md") &&
      not String.contains?(filename, ["/", "\\", <<0>>]) && filename != ".md"
  end

  defp valid_filename?(_), do: false

  defp check_filename(filename) do
    if valid_filename?(filename), do: :ok, else: {:error, "Invalid card filename."}
  end

  defp check_regular_file(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular}} -> :ok
      {:ok, _} -> {:error, "The card must be a regular Markdown file."}
      error -> file_result(error, "open #{Path.basename(path)}")
    end
  end

  defp file_result({:error, reason}, action) do
    {:error, "Could not #{action}: #{:file.format_error(reason)}."}
  end

  defp file_result(result, _action), do: result
end
