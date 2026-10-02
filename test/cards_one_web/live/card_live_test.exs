defmodule CardsOneWeb.CardLiveTest do
  use CardsOneWeb.ConnCase

  import Phoenix.LiveViewTest
  import CardsOne.CardsFixtures

  alias CardsOne.Cards

  setup do
    catalogue_fixture()
  end

  test "creates a timestamp-named file using only the Markdown input", %{
    conn: conn,
    directory: directory
  } do
    {:ok, index, _html} = live(conn, ~p"/cards")
    assert has_element?(index, "#cards")

    {:ok, editor, _html} =
      index |> element("#new-card") |> render_click() |> follow_redirect(conn, ~p"/cards/new")

    assert has_element?(editor, "#card-form textarea[name='card[body]']")
    refute has_element?(editor, "#card-form input[name='card[filename]']")

    body = "# Heading\n\n**Markdown** with a [link](https://example.com).\n"

    {:ok, index, _html} =
      editor
      |> form("#card-form", card: %{body: body})
      |> render_submit()
      |> follow_redirect(conn, ~p"/cards")

    assert {:ok, [card]} = Cards.list_cards()
    assert File.read!(Path.join(directory, card.filename)) == body
    assert has_element?(index, ~s([id="show-#{card.filename}"]), card.filename)
    assert has_element?(index, "#flash-info", "Card created successfully")
  end

  test "updates a file and keeps its filename", %{conn: conn, directory: directory} do
    card = card_fixture()
    {:ok, index, _html} = live(conn, ~p"/cards")

    {:ok, editor, _html} =
      index
      |> element(~s([id="edit-#{card.filename}"]))
      |> render_click()
      |> follow_redirect(conn, ~p"/cards/#{card}/edit")

    assert has_element?(editor, "#card-form textarea", card.body)

    {:ok, index, _html} =
      editor
      |> form("#card-form", card: %{body: "Updated **note**"})
      |> render_submit()
      |> follow_redirect(conn, ~p"/cards")

    assert File.read!(Path.join(directory, card.filename)) == "Updated **note**"
    assert File.ls!(directory) == [card.filename]
    assert has_element?(index, ~s([id="cards-#{card.filename}"]), "Updated **note**")
  end

  test "deletes the file and removes the listing", %{conn: conn, directory: directory} do
    card = card_fixture()
    {:ok, index, _html} = live(conn, ~p"/cards")
    assert has_element?(index, ~s([id="cards-#{card.filename}"]))

    index |> element(~s([id="delete-#{card.filename}"])) |> render_click()

    refute has_element?(index, ~s([id="cards-#{card.filename}"]))
    refute File.exists?(Path.join(directory, card.filename))
    assert has_element?(index, "#flash-info", "Card deleted successfully")
  end

  test "reads the full Markdown literally and does not activate HTML or scripts", %{conn: conn} do
    body =
      "# Title\n\n<script>alert('x')</script><img src=x onerror=alert(1)>\n\n```html\n<b>code</b>\n```\n\n    <script>indented</script>\n"

    card = card_fixture(%{body: body})
    {:ok, show, _html} = live(conn, ~p"/cards/#{card}")

    assert has_element?(show, "#card-title", card.filename)
    assert has_element?(show, "#card-body")
    refute has_element?(show, "#card-body script")
    refute has_element?(show, "#card-body img")
    refute has_element?(show, "#card-body b")
    refute has_element?(show, "#card-body h1")

    assert show
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("#card-body")
           |> LazyHTML.text() == body
  end

  test "editing from the read view returns to the card", %{conn: conn, directory: directory} do
    card = card_fixture()
    {:ok, show, _html} = live(conn, ~p"/cards/#{card}")

    {:ok, editor, _html} =
      show
      |> element("#edit-card")
      |> render_click()
      |> follow_redirect(conn, ~p"/cards/#{card}/edit?return_to=show")

    {:ok, show, _html} =
      editor
      |> form("#card-form", card: %{body: "## Changed\n"})
      |> render_submit()
      |> follow_redirect(conn, ~p"/cards/#{card}")

    assert has_element?(show, "#card-title", card.filename)
    assert has_element?(show, "#card-body", "## Changed")
    assert File.read!(Path.join(directory, card.filename)) == "## Changed\n"
  end

  test "save failure leaves the editor open and preserves the original file", %{
    conn: conn,
    directory: directory
  } do
    card = card_fixture()
    {:ok, editor, _html} = live(conn, ~p"/cards/#{card}/edit")
    File.chmod!(directory, 0o555)

    try do
      editor |> form("#card-form", card: %{body: "Cannot save"}) |> render_submit()
      assert has_element?(editor, "#card-form")
      assert has_element?(editor, "#flash-error", "not writable")
      assert File.read!(Path.join(directory, card.filename)) == card.body
    after
      File.chmod!(directory, 0o755)
    end
  end

  test "delete failure leaves the listing visible", %{conn: conn, directory: directory} do
    card = card_fixture()
    {:ok, index, _html} = live(conn, ~p"/cards")
    File.chmod!(directory, 0o555)

    try do
      index |> element(~s([id="delete-#{card.filename}"])) |> render_click()
      assert has_element?(index, ~s([id="cards-#{card.filename}"]))
      assert has_element?(index, "#flash-error")
      assert File.exists?(Path.join(directory, card.filename))
    after
      File.chmod!(directory, 0o755)
    end
  end

  test "missing cards redirect with a notice instead of crashing", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/cards", flash: %{"error" => _}}}} =
             live(conn, ~p"/cards/missing.md")

    assert {:error, {:live_redirect, %{to: "/cards", flash: %{"error" => _}}}} =
             live(conn, ~p"/cards/missing.md/edit")
  end

  test "an unconfigured catalogue produces notices", %{conn: conn, config_file: config_file} do
    File.write!(config_file, "catalogue-directory = ''\n")
    {:ok, index, _html} = live(conn, ~p"/cards")
    assert has_element?(index, "#flash-error", "Set catalogue-directory")

    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => _}}}} =
             live(conn, ~p"/cards/new")
  end
end
