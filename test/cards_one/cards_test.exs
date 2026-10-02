defmodule CardsOne.CardsTest do
  use CardsOne.DataCase

  alias CardsOne.Cards
  alias CardsOne.Cards.Card
  alias CardsOne.Cards.CardRecord
  import CardsOne.CardsFixtures

  setup do
    catalogue_fixture()
  end

  test "CRUD writes files first and maintains their SQLite copies", %{directory: directory} do
    before = System.system_time(:second)

    body =
      "# A card\n\n**Markdown** and <script>alert('hello')</script>\n\n```html\n<b>code</b>\n```\n"

    assert {:ok, %Card{} = card} = Cards.create_card(%{body: body, filename: "supplied.md"})
    assert card.filename =~ ~r/^\d+\.md$/
    assert String.to_integer(Path.rootname(card.filename)) in before..System.system_time(:second)
    assert card.id == card.filename
    path = Path.join(directory, card.filename)
    assert File.read!(path) == body
    assert Repo.get_by!(CardRecord, filename: card.filename).body == body
    assert {:ok, [^card]} = Cards.list_cards()
    assert {:ok, ^card} = Cards.get_card(card.filename)

    assert {:ok, updated} =
             Cards.update_card(card, %{body: "## Updated\n", filename: "renamed.md"})

    assert updated.filename == card.filename
    assert File.read!(path) == "## Updated\n"
    assert Repo.get_by!(CardRecord, filename: card.filename).body == "## Updated\n"
    assert File.ls!(directory) == [card.filename]
    assert {:ok, ^updated} = Cards.get_card(card.filename)

    assert {:ok, ^updated} = Cards.delete_card(updated)
    refute File.exists?(path)
    assert {:ok, []} = Cards.list_cards()
    assert {:error, _} = Cards.get_card(card.filename)
    refute Repo.get_by(CardRecord, filename: card.filename)
  end

  test "rapid creation never overwrites an existing card", %{directory: directory} do
    cards =
      for number <- 1..20 do
        {:ok, card} = Cards.create_card(%{body: "Card #{number}"})
        card
      end

    assert length(Enum.uniq_by(cards, & &1.filename)) == 20
    assert length(File.ls!(directory)) == 20

    for card <- cards do
      assert File.read!(Path.join(directory, card.filename)) == card.body
    end
  end

  test "blank Markdown and whitespace are preserved", %{directory: directory} do
    assert {:ok, card} = Cards.create_card(%{body: ""})
    assert File.read!(Path.join(directory, card.filename)) == ""
    assert {:ok, card} = Cards.update_card(card, %{body: " \n\t"})
    assert File.read!(Path.join(directory, card.filename)) == " \n\t"
  end

  test "invalid body values do not create or change files", %{directory: directory} do
    assert {:error, %Ecto.Changeset{}} = Cards.create_card(%{body: nil})
    assert {:error, %Ecto.Changeset{}} = Cards.create_card(%{body: %{invalid: "text"}})
    assert {:error, %Ecto.Changeset{}} = Cards.create_card(%{body: <<255>>})
    assert File.ls!(directory) == []
    card = card_fixture()
    assert {:error, %Ecto.Changeset{}} = Cards.update_card(card, %{body: nil})
    assert File.read!(Path.join(directory, card.filename)) == card.body
  end

  test "external file creation, edits and deletion are reflected", %{directory: directory} do
    path = Path.join(directory, "1790921230.md")
    File.write!(path, "Created outside the app")
    assert {:ok, [card]} = Cards.list_cards()
    assert card.filename == "1790921230.md"
    File.write!(path, "Edited outside the app")
    assert {:ok, %{body: "Edited outside the app"}} = Cards.get_card(card.filename)
    File.rm!(path)
    assert {:ok, []} = Cards.list_cards()
    assert {:error, _} = Cards.update_card(card, %{body: "Do not recreate"})
    refute File.exists?(path)
  end

  test "only regular Markdown files are listed", %{directory: directory, root: root} do
    File.write!(Path.join(directory, "note.md"), "A note")
    File.write!(Path.join(directory, "other.txt"), "Ignore")
    File.mkdir!(Path.join(directory, "nested.md"))
    target = Path.join(root, "outside.md")
    File.write!(target, "Outside")
    File.ln_s!(target, Path.join(directory, "linked.md"))

    assert {:ok, [%{filename: "note.md"}]} = Cards.list_cards()
    assert {:error, _} = Cards.get_card("linked.md")
    assert {:error, _} = Cards.get_card("nested.md")
    assert File.read!(target) == "Outside"
  end

  test "filenames cannot escape the catalogue", %{root: root} do
    File.write!(Path.join(root, "outside.md"), "Outside")

    for filename <- ["../outside.md", "/tmp/outside.md", "..\\outside.md", "bad\0.md", "note.txt"] do
      assert {:error, _} = Cards.get_card(filename)
    end

    card = card_fixture()
    forged = %{card | filename: "../outside.md"}
    assert {:error, _} = Cards.update_card(forged, %{body: "Overwrite"})
    assert {:error, _} = Cards.delete_card(forged)
    assert File.read!(Path.join(root, "outside.md")) == "Outside"
  end

  test "a catalogue change cannot redirect an open card's writes", %{
    directory: directory,
    config_file: config_file,
    root: root
  } do
    card = card_fixture()
    other = Path.join(root, "other")
    File.mkdir!(other)
    File.write!(Path.join(other, card.filename), "Different card")
    File.write!(config_file, "catalogue-directory = '#{other}'\n")

    assert {:error, _} = Cards.update_card(card, %{body: "Changed"})
    assert {:error, _} = Cards.delete_card(card)
    assert File.read!(Path.join(other, card.filename)) == "Different card"
    assert File.read!(Path.join(directory, card.filename)) == card.body
  end

  test "filesystem failures are returned and the original file survives", %{directory: directory} do
    card = card_fixture()
    File.chmod!(directory, 0o555)

    try do
      assert {:error, _} = Cards.create_card(%{body: "New"})
      assert {:error, _} = Cards.update_card(card, %{body: "Changed"})
      assert {:error, _} = Cards.delete_card(card)
      assert File.read!(Path.join(directory, card.filename)) == card.body
    after
      File.chmod!(directory, 0o755)
    end
  end

  test "invalid configuration is returned as an error", %{config_file: config_file} do
    File.write!(config_file, "catalogue-directory = ''\n")
    assert {:error, _} = Cards.list_cards()
    assert {:error, _} = Cards.get_card("1790921230.md")
    assert {:error, _} = Cards.create_card(%{body: "New"})
  end

  test "non UTF-8 files report an error", %{directory: directory} do
    File.write!(Path.join(directory, "invalid.md"), <<255>>)
    assert {:error, _} = Cards.get_card("invalid.md")
    assert {:error, _} = Cards.list_cards()
  end
end
