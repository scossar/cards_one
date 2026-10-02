defmodule CardsOne.Repo do
  use Ecto.Repo,
    otp_app: :cards_one,
    adapter: Ecto.Adapters.SQLite3

  @impl true
  def init(_type, config) do
    {:ok, Keyword.put(config, :load_extensions, [SqliteVec.path()])}
  end
end
