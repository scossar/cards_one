defmodule CardsOne.CardsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `CardsOne.Cards` context.
  """

  @doc """
  Generate a card.
  """
  def card_fixture(attrs \\ %{}) do
    {:ok, card} =
      attrs
      |> Enum.into(%{
        body: "some body",
        filename: "some filename"
      })
      |> CardsOne.Cards.create_card()

    card
  end
end
