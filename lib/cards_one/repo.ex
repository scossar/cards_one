defmodule CardsOne.Repo do
  use Ecto.Repo,
    otp_app: :cards_one,
    adapter: Ecto.Adapters.SQLite3
end
