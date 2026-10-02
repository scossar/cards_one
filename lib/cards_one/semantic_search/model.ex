defmodule CardsOne.SemanticSearch.Model do
  @moduledoc "Local MiniLM embeddings. Whole-card input is temporarily limited to 256 tokens."

  @model "sentence-transformers/all-MiniLM-L6-v2"
  @revision "1110a243fdf4706b3f48f1d95db1a4f5529b4d41"

  def key, do: "#{@model}@#{@revision}:mean:l2:whole-card-v1:256"

  def load do
    repository =
      case System.get_env("CARDS_ONE_MODEL_DIR") do
        nil ->
          {:hf, @model,
           revision: @revision,
           cache_dir:
             System.get_env("CARDS_ONE_MODEL_CACHE") || Path.expand("~/.cache/cards_one/models"),
           offline: System.get_env("CARDS_ONE_MODEL_OFFLINE") == "true"}

        directory ->
          {:local, directory}
      end

    with {:ok, model} <- Bumblebee.load_model(repository),
         {:ok, tokenizer} <- Bumblebee.load_tokenizer(repository) do
      tokenizer = Bumblebee.configure(tokenizer, length: 256)

      serving =
        Bumblebee.Text.text_embedding(model, tokenizer,
          output_attribute: :hidden_state,
          output_pool: :mean_pooling,
          embedding_processor: :l2_norm,
          compile: [batch_size: 1, sequence_length: 256],
          defn_options: [compiler: EXLA, client: :host]
        )

      # Compile and verify inference before advertising readiness.
      %{embedding: embedding} = Nx.Serving.run(serving, "A short note.")
      {384} = Nx.shape(embedding)
      {:ok, serving}
    end
  end

  def embed(text) do
    case CardsOne.SemanticSearch.Worker.status() do
      :ready ->
        %{embedding: embedding} = Nx.Serving.batched_run(CardsOne.SemanticSearch.Serving, text)
        {:ok, embedding |> Nx.as_type(:f32) |> Nx.to_binary()}

      status ->
        {:error, status}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    :exit, _ -> {:error, :unavailable}
  end
end
