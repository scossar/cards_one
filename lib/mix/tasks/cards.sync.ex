defmodule Mix.Tasks.Cards.Sync do
  use Mix.Task

  @shortdoc "Rebuilds the SQLite card index from the configured catalogue"
  @moduledoc """
  Creates the database if necessary, runs migrations, then reconciles the card
  index with the configured catalogue. Existing Markdown files are not changed.

      mix cards.sync
  """

  @impl true
  def run(_args) do
    Mix.Task.run("ecto.create", ["--quiet"])
    Mix.Task.run("ecto.migrate", ["--quiet"])
    Mix.Task.run("app.start")

    case CardsOne.Cards.sync_catalogue() do
      {:ok, count} -> Mix.shell().info("Synchronized #{count} cards from the catalogue")
      {:error, reason} -> Mix.raise("Cannot synchronize the catalogue: #{reason}")
    end
  end
end
