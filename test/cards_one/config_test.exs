defmodule CardsOne.ConfigTest do
  use ExUnit.Case, async: true

  alias CardsOne.Config

  setup do
    root = Path.join(System.tmp_dir!(), "cards-one-config-#{Ecto.UUID.generate()}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, config_file: Path.join(root, "settings/config.toml")}
  end

  test "creates the config with an empty catalogue and preserves subsequent edits", %{
    config_file: config_file
  } do
    assert :ok = Config.ensure_file(config_file)
    assert Toml.decode_file!(config_file) == %{"catalogue-directory" => ""}

    edited = "# My cards\ncatalogue-directory = '/my/cards'\n"
    File.write!(config_file, edited)
    assert :ok = Config.ensure_file(config_file)
    assert File.read!(config_file) == edited
  end

  test "reports an empty or omitted catalogue", %{config_file: config_file} do
    assert {:error, notice} = Config.catalogue_directory(config_file)
    assert notice =~ config_file
    assert notice =~ "Set catalogue-directory"

    File.write!(config_file, "# No directory set\n")
    assert {:error, _} = Config.catalogue_directory(config_file)
  end

  test "accepts a writable directory and leaves its contents untouched", %{
    root: root,
    config_file: config_file
  } do
    directory = Path.join(root, "cards with spaces")
    File.mkdir!(directory)
    File.write!(Path.join(directory, "existing.md"), "Keep this card")
    write_config(config_file, directory)

    assert {:ok, ^directory} = Config.catalogue_directory(config_file)
    assert File.ls!(directory) == ["existing.md"]
    assert File.read!(Path.join(directory, "existing.md")) == "Keep this card"
  end

  test "resolves relative paths from the config directory", %{config_file: config_file} do
    directory = Path.join(Path.dirname(config_file), "cards")
    File.mkdir_p!(directory)
    File.write!(config_file, "catalogue-directory = 'cards' # relative path\n")

    assert {:ok, ^directory} = Config.catalogue_directory(config_file)
  end

  test "reports a missing directory without creating it", %{root: root, config_file: config_file} do
    directory = Path.join(root, "missing")
    write_config(config_file, directory)

    assert {:error, notice} = Config.catalogue_directory(config_file)
    assert notice =~ "does not exist"
    refute File.exists?(directory)
  end

  test "rejects a regular file as the catalogue", %{root: root, config_file: config_file} do
    directory = Path.join(root, "card.md")
    File.write!(directory, "A card")
    write_config(config_file, directory)

    assert {:error, notice} = Config.catalogue_directory(config_file)
    assert notice =~ "not a directory"
  end

  test "reports a directory that cannot be written", %{root: root, config_file: config_file} do
    directory = Path.join(root, "read-only")
    File.mkdir!(directory)
    write_config(config_file, directory)
    File.chmod!(directory, 0o555)

    try do
      assert {:error, notice} = Config.catalogue_directory(config_file)
      assert notice =~ "not writable"
      assert File.ls!(directory) == []
    after
      File.chmod!(directory, 0o755)
    end
  end

  test "reports malformed TOML and non-string settings", %{config_file: config_file} do
    Config.ensure_file(config_file)
    File.write!(config_file, "catalogue-directory = \"unterminated")
    assert {:error, notice} = Config.catalogue_directory(config_file)
    assert notice =~ "Invalid TOML"

    File.write!(config_file, "catalogue-directory = 42\n")
    assert {:error, notice} = Config.catalogue_directory(config_file)
    assert notice =~ "must be a string"
  end

  test "reports unreadable config and failure to create config", %{root: root} do
    config_file = Path.join(root, "unreadable.toml")
    File.write!(config_file, "catalogue-directory = ''\n")
    File.chmod!(config_file, 0o000)

    try do
      assert {:error, notice} = Config.catalogue_directory(config_file)
      assert notice =~ "Cannot read config file"
    after
      File.chmod!(config_file, 0o644)
    end

    blocker = Path.join(root, "regular-file")
    File.write!(blocker, "")
    assert {:error, notice} = Config.catalogue_directory(Path.join(blocker, "config.toml"))
    assert notice =~ "Cannot create config file"
  end

  defp write_config(config_file, directory) do
    File.mkdir_p!(Path.dirname(config_file))
    File.write!(config_file, "catalogue-directory = #{Jason.encode!(directory)}\n")
  end
end
