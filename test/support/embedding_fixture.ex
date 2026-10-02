defmodule CardsOne.EmbeddingFixture do
  @moduledoc false
  def key, do: "test-model-v1"

  def embed(text) do
    coordinate = if String.contains?(text, ["car", "vehicle", "automobile"]), do: 0, else: 1
    values = for index <- 0..383, do: if(index == coordinate, do: 1.0, else: 0.0)
    {:ok, Nx.tensor(values, type: :f32) |> Nx.to_binary()}
  end
end
