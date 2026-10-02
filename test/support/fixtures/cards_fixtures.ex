defmodule CardsOne.CardsFixtures do
  @moduledoc "Filesystem fixtures for cards, isolated from the user's catalogue."

  def catalogue_fixture do
    root = Path.join(System.tmp_dir!(), "cards-one-catalogue-#{Ecto.UUID.generate()}")
    directory = Path.join(root, "cards")
    config_file = Path.join(root, "config.toml")
    File.mkdir_p!(directory)
    File.write!(config_file, "catalogue-directory = #{Jason.encode!(directory)}\n")
    previous = Application.fetch_env!(:cards_one, :config_file)
    Application.put_env(:cards_one, :config_file, config_file)

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:cards_one, :config_file, previous)
      File.rm_rf!(root)
    end)

    %{directory: directory, config_file: config_file, root: root}
  end

  def card_fixture(attrs \\ %{}) do
    {:ok, card} = attrs |> Enum.into(%{body: "some body"}) |> CardsOne.Cards.create_card()
    card
  end
end
