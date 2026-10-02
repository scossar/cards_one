defmodule CardsOne.Repo.Migrations.AddUniqueIndexToCardsFilename do
  use Ecto.Migration

  def change do
    create unique_index(:cards, [:filename])
  end
end
