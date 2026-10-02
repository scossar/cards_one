defmodule CardsOneWeb.HomeLiveTest do
  use CardsOneWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    root = Path.join(System.tmp_dir!(), "cards-one-home-#{Ecto.UUID.generate()}")
    File.mkdir_p!(root)
    config_file = Path.join(root, "config.toml")
    previous = Application.fetch_env!(:cards_one, :config_file)
    Application.put_env(:cards_one, :config_file, config_file)

    on_exit(fn ->
      Application.put_env(:cards_one, :config_file, previous)
      File.rm_rf!(root)
    end)

    %{root: root, config_file: config_file}
  end

  test "creates config and shows a notice when catalogue is empty", %{
    conn: conn,
    config_file: config_file
  } do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#open-cards[href='/cards']")
    assert has_element?(view, "#flash-info", "Set catalogue-directory")
    assert has_element?(view, "#flash-info", config_file)
    assert Toml.decode_file!(config_file) == %{"catalogue-directory" => ""}
  end

  test "shows a notice for a missing directory", %{
    conn: conn,
    root: root,
    config_file: config_file
  } do
    File.write!(config_file, "catalogue-directory = '#{root}/missing'\n")
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#flash-info", "does not exist")
  end

  test "shows a notice for an unwritable directory", %{
    conn: conn,
    root: root,
    config_file: config_file
  } do
    directory = Path.join(root, "read-only")
    File.mkdir!(directory)
    File.write!(config_file, "catalogue-directory = '#{directory}'\n")
    File.chmod!(directory, 0o555)

    try do
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#flash-info", "not writable")
    after
      File.chmod!(directory, 0o755)
    end
  end

  test "rereads edits and removes the notice on the next visit", %{
    conn: conn,
    root: root,
    config_file: config_file
  } do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#flash-info")

    directory = Path.join(root, "cards")
    File.mkdir!(directory)
    File.write!(config_file, "catalogue-directory = '#{directory}'\n")

    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#flash-info")
    assert has_element?(view, "#open-cards[href='/cards']")
    assert File.ls!(directory) == []
  end

  test "shows a notice instead of crashing on malformed TOML", %{
    conn: conn,
    config_file: config_file
  } do
    File.write!(config_file, "catalogue-directory = \"unterminated")
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#flash-info", "Invalid TOML")
  end
end
