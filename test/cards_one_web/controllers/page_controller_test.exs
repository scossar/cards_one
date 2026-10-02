defmodule CardsOneWeb.PageControllerTest do
  use CardsOneWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("a[href='/cards']") |> Enum.count() == 1
  end
end
