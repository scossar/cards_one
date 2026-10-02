defmodule CardsOne.Repo do
  use Ecto.Repo,
    otp_app: :cards_one,
    adapter: Ecto.Adapters.SQLite3

  @impl true
  def init(_type, config) do
    extensions = [CardsOne.SQLiteExtension.path!() | Keyword.get(config, :load_extensions, [])]
    {:ok, Keyword.put(config, :load_extensions, Enum.uniq(extensions))}
  end
end
