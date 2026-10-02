defmodule CardsOneWeb.SearchLiveTest do
  use CardsOneWeb.ConnCase

  import Phoenix.LiveViewTest
  import CardsOne.CardsFixtures

  setup do
    catalogue_fixture()
  end

  test "searches from the form and links results to cards", %{conn: conn} do
    matching = card_fixture(%{body: "Quick brown fox"})
    card_fixture(%{body: "An unrelated cat"})
    {:ok, view, _html} = live(conn, ~p"/search")
    assert has_element?(view, "#header-search[href='/search']")
    assert has_element?(view, "#search-form")
    refute has_element?(view, "#search-summary")

    view |> form("#search-form", search: %{query: ~s("brown fox")}) |> render_submit()
    assert_patch(view, ~p"/search?#{%{q: ~s("brown fox")}}")
    assert has_element?(view, "#search-summary", "1 result")

    assert has_element?(
             view,
             "#search-results a[href='/cards/#{matching.filename}']",
             matching.filename
           )

    view |> element("#search-results a[href='/cards/#{matching.filename}']") |> render_click()
    assert_redirect(view, ~p"/cards/#{matching}")
  end

  test "loading a query URL restores the query and its results", %{conn: conn} do
    card = card_fixture(%{body: "Savedquery"})
    {:ok, view, _html} = live(conn, ~p"/search?#{%{q: "Savedquery"}}")
    assert has_element?(view, "#search-query[value='Savedquery']")
    assert has_element?(view, "#search-results a[href='/cards/#{card.filename}']")
  end

  test "a new search clears old results and empty input resets the page", %{conn: conn} do
    card_fixture(%{body: "Firstquery"})
    {:ok, view, _html} = live(conn, ~p"/search?#{%{q: "Firstquery"}}")
    assert has_element?(view, "#search-results > article")

    view |> form("#search-form", search: %{query: "absentword"}) |> render_submit()
    assert has_element?(view, "#search-empty")
    refute has_element?(view, "#search-results > article")

    view |> form("#search-form", search: %{query: " "}) |> render_submit()
    assert_patch(view, ~p"/search")
    refute has_element?(view, "#search-summary")
    refute has_element?(view, "#search-empty")
  end

  test "malformed queries show a plain notice and recover on the next search", %{conn: conn} do
    card = card_fixture(%{body: "Recoverquery"})
    {:ok, view, _html} = live(conn, ~p"/search?#{%{q: "Recoverquery"}}")
    view |> form("#search-form", search: %{query: ~s("unterminated)}) |> render_submit()

    assert has_element?(view, "#flash-error", "could not be understood")
    refute has_element?(view, "#search-results > article")
    refute has_element?(view, "#search-empty")

    view |> form("#search-form", search: %{query: "Recoverquery"}) |> render_submit()
    refute has_element?(view, "#flash-error")
    assert has_element?(view, "#search-results a[href='/cards/#{card.filename}']")
  end

  test "excerpts display HTML and scripts as text", %{conn: conn} do
    card_fixture(%{body: "Matchword <script>alert(1)</script><img src=x onerror=alert(1)>"})
    {:ok, view, _html} = live(conn, ~p"/search?#{%{q: "Matchword"}}")
    assert has_element?(view, "#search-results p", "<script>alert(1)</script>")
    refute has_element?(view, "#search-results script")
    refute has_element?(view, "#search-results img")
  end

  test "pagination keeps the query and replaces the streamed page", %{conn: conn} do
    for _ <- 1..21, do: card_fixture(%{body: "Pageword"})
    {:ok, view, _html} = live(conn, ~p"/search?#{%{q: "Pageword"}}")
    assert has_element?(view, "#search-summary", "21 results")
    assert has_element?(view, "#search-page", "Page 1 of 2")

    assert view
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("#search-results > article")
           |> Enum.count() == 20

    view |> element("#search-next") |> render_click()
    assert_patch(view, ~p"/search?#{%{q: "Pageword", page: 2}}")
    assert has_element?(view, "#search-page", "Page 2 of 2")

    assert view
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("#search-results > article")
           |> Enum.count() == 1

    refute has_element?(view, "#search-next")

    view |> element("#search-previous") |> render_click()
    assert has_element?(view, "#search-page", "Page 1 of 2")
  end

  test "database index failures show a plain notice instead of stale results", %{conn: conn} do
    card_fixture(%{body: "Indexword"})
    CardsOne.Repo.query!("DROP TABLE cards_fts")
    {:ok, view, _html} = live(conn, ~p"/search?#{%{q: "Indexword"}}")
    assert has_element?(view, "#flash-error", "temporarily unavailable")
    refute has_element?(view, "#search-results > article")
  end

  test "semantic form search runs asynchronously and preserves its mode", %{conn: conn} do
    Application.put_env(:cards_one, :embedding_provider, CardsOne.EmbeddingFixture)
    on_exit(fn -> Application.delete_env(:cards_one, :embedding_provider) end)
    matching = card_fixture(%{body: "An automobile <script>alert(1)</script>"})
    assert {:ok, 1} = CardsOne.SemanticSearch.index_pending()
    {:ok, view, _} = live(conn, ~p"/search")
    view |> form("#search-form", search: %{query: "vehicle", mode: "semantic"}) |> render_submit()
    assert_patch(view, ~p"/search?#{%{q: "vehicle", mode: "semantic"}}")
    render_async(view)
    assert has_element?(view, "#search-mode option[value='semantic'][selected]")
    assert has_element?(view, "#search-results a[href='/cards/#{matching.filename}']")
    refute has_element?(view, "#search-loading")
    refute has_element?(view, "#search-results script")
    view |> form("#search-form", search: %{query: "automobile", mode: "text"}) |> render_submit()
    assert_patch(view, ~p"/search?#{%{q: "automobile"}}")
    assert has_element?(view, "#search-results a[href='/cards/#{matching.filename}']")
  end

  test "semantic model unavailability leaves text search usable", %{conn: conn} do
    card = card_fixture(%{body: "Fallbackword"})
    {:ok, view, _} = live(conn, ~p"/search?#{%{q: "vehicle", mode: "semantic"}}")
    render_async(view)
    assert has_element?(view, "#flash-error")

    view
    |> form("#search-form", search: %{query: "Fallbackword", mode: "text"})
    |> render_submit()

    assert has_element?(view, "#search-results a[href='/cards/#{card.filename}']")
  end
end
