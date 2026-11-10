defmodule ElxAgentTutorial.Tools.KnowledgeBase do
  @moduledoc """
  Module 4 - retrieval as a tool (RAG).

  The classic RAG pipeline - embed your documents once, embed the query at
  search time, return the closest chunks - IS the tool here. The *agent*
  decides when to call it, how to phrase the query, and whether to search
  again after a weak result.

  Embedding is exactly what [Bumblebee](https://hexdocs.pm/bumblebee) is for
  - it loads a model straight from the Hugging Face Hub
  (`sentence-transformers/all-MiniLM-L6-v2`, ~90MB, downloaded once and
  cached under `XDG_CACHE_HOME`/`.cache/bumblebee`) and runs it with
  `Nx`/`EXLA`. No vector database needed at this scale - cosine similarity
  over a small `Nx` tensor is plenty.

  Built as a stateful tool: `build/1` loads and embeds the corpus once, then
  returns a `%Tool{}` whose `forward` closes over that state.
  """

  alias ElxAgentTutorial.Tool

  @model "sentence-transformers/all-MiniLM-L6-v2"
  @default_top_k 3

  @doc """
  Load every `*.md` file in `docs_dir`, split into paragraph chunks, embed
  them, and return a ready-to-use `%Tool{}`. Raises if the directory has no
  usable markdown.

  Returns `{tool, chunks, sources_agent}` where `sources_agent` is a tiny
  `Agent` process tracking which source files retrieval actually hit, used
  for the run summary.
  """
  def build(docs_dir, top_k \\ @default_top_k) do
    chunks = load_chunks(docs_dir)
    quiet_hf_downloads()

    {:ok, model_info} = Bumblebee.load_model({:hf, @model})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, @model})

    serving =
      Bumblebee.Text.text_embedding(model_info, tokenizer,
        output_pool: :mean_pooling,
        output_attribute: :hidden_state,
        embedding_processor: :l2_norm
      )

    embeddings = embed_all(serving, Enum.map(chunks, & &1.text))

    {:ok, sources_agent} = Agent.start_link(fn -> MapSet.new() end)

    tool =
      Tool.from_fun(
        "knowledge_base",
        "Semantic search over the local knowledge base of internal documents. " <>
          "Use it for questions about the company, its products, or this tutorial's " <>
          "agent framework. Returns the most relevant passages, each prefixed with its source file.",
        %{"query" => %{type: "string", doc: "A natural-language question or search phrase."}},
        &search(&1, serving, chunks, embeddings, top_k, sources_agent)
      )

    {tool, chunks, sources_agent}
  end

  defp load_chunks(docs_dir) do
    chunks =
      docs_dir
      |> Path.join("*.md")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.flat_map(fn path ->
        source = Path.basename(path)

        path
        |> File.read!()
        |> String.split(~r/\n\s*\n/)
        |> Enum.map(&String.trim/1)
        # skip headings and short one-line fragments
        |> Enum.filter(&(String.length(&1) > 40))
        |> Enum.map(&%{source: source, text: &1})
      end)

    if chunks == [] do
      raise "No .md content found in #{docs_dir}"
    end

    chunks
  end

  # Silences the progress bar Bumblebee prints while downloading/loading a
  # model from the Hub.
  defp quiet_hf_downloads do
    Application.put_env(:bumblebee, :progress_bar_enabled, false)
  end

  defp embed_all(serving, texts) do
    vectors =
      Nx.Serving.run(serving, texts)
      |> Enum.map(& &1.embedding)

    Nx.stack(vectors)
  end

  @doc "Source files retrieval actually returned passages from, sorted."
  def sources_seen(sources_agent), do: Agent.get(sources_agent, &Enum.sort(MapSet.to_list(&1)))

  defp search(%{"query" => query}, serving, chunks, embeddings, top_k, sources_agent) do
    [%{embedding: query_vec}] = Nx.Serving.run(serving, [query])

    scores =
      embeddings
      |> Nx.dot([1], query_vec, [0])
      |> Nx.to_flat_list()

    hits =
      chunks
      |> Enum.zip(scores)
      |> Enum.sort_by(fn {_chunk, score} -> score end, :desc)
      |> Enum.take(top_k)
      |> Enum.map(fn {chunk, _score} -> chunk end)

    Agent.update(sources_agent, fn seen ->
      Enum.reduce(hits, seen, &MapSet.put(&2, &1.source))
    end)

    hits
    |> Enum.map_join("\n\n---\n\n", fn %{source: source, text: text} -> "[#{source}]\n#{text}" end)
  end
end
