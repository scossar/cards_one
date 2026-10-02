defmodule CardsOne.Repo.Migrations.CreateCards do
  use Ecto.Migration

  def change do
    create table(:cards) do
      add :filename, :string
      add :body, :text

      timestamps(type: :utc_datetime)
    end
  end
end
