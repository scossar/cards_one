defmodule CardsOne.CardsTest do
  use CardsOne.DataCase

  alias CardsOne.Cards

  describe "cards" do
    alias CardsOne.Cards.Card

    import CardsOne.CardsFixtures

    @invalid_attrs %{filename: nil, body: nil}

    test "list_cards/0 returns all cards" do
      card = card_fixture()
      assert Cards.list_cards() == [card]
    end

    test "get_card!/1 returns the card with given id" do
      card = card_fixture()
      assert Cards.get_card!(card.id) == card
    end

    test "create_card/1 with valid data creates a card" do
      valid_attrs = %{filename: "some filename", body: "some body"}

      assert {:ok, %Card{} = card} = Cards.create_card(valid_attrs)
      assert card.filename == "some filename"
      assert card.body == "some body"
    end

    test "create_card/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Cards.create_card(@invalid_attrs)
    end

    test "update_card/2 with valid data updates the card" do
      card = card_fixture()
      update_attrs = %{filename: "some updated filename", body: "some updated body"}

      assert {:ok, %Card{} = card} = Cards.update_card(card, update_attrs)
      assert card.filename == "some updated filename"
      assert card.body == "some updated body"
    end

    test "update_card/2 with invalid data returns error changeset" do
      card = card_fixture()
      assert {:error, %Ecto.Changeset{}} = Cards.update_card(card, @invalid_attrs)
      assert card == Cards.get_card!(card.id)
    end

    test "delete_card/1 deletes the card" do
      card = card_fixture()
      assert {:ok, %Card{}} = Cards.delete_card(card)
      assert_raise Ecto.NoResultsError, fn -> Cards.get_card!(card.id) end
    end

    test "change_card/1 returns a card changeset" do
      card = card_fixture()
      assert %Ecto.Changeset{} = Cards.change_card(card)
    end
  end
end
