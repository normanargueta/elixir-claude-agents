# Module 4 - A retrieval-augmented (RAG) agent
# ============================================
#
# An LLM only knows what was in its training data. To answer questions about
# YOUR documents, give the agent a tool that searches them.
#
# The classic "RAG pipeline" is: embed your documents into vectors once, then
# at query time embed the question and return the closest chunks. Here that
# pipeline IS a tool - `ElxAgentTutorial.Tools.KnowledgeBase`. The key
# difference from a fixed RAG chain: the *agent* decides when to search, how
# to phrase the query, and whether to search again with a better query after
# seeing weak results.
#
# This is the Hugging-Face-native piece of this tutorial: KnowledgeBase.build/1
# uses Bumblebee to load `sentence-transformers/all-MiniLM-L6-v2` straight
# from the Hub (~90MB, downloads once, cached locally), and Nx for the
# cosine-similarity search - no vector database needed at this scale.
#
# The knowledge base is the markdown in `priv/data/`. The capstone reuses this
# exact retriever and directory.
#
# Run it:
#     mix run scripts/04_rag_agent.exs
# (first run also downloads the embedding model - once, can take a minute)

alias ElxAgentTutorial.{Step, ToolCallingAgent, Tools}

data_dir = Path.join([__DIR__, "..", "priv", "data"])

question =
  "According to our internal docs, what is the refund window for the " <>
    "Pro plan, and who do I escalate a billing dispute to?"

{kb_tool, chunks, source_agent} = Tools.KnowledgeBase.build(data_dir)
agent = ToolCallingAgent.new(tools: [kb_tool], max_steps: 6)

IO.puts("Question: #{question}")
IO.puts("Knowledge base: #{length(chunks)} chunks from #{Path.expand(data_dir)}\n")

case ToolCallingAgent.run(agent, question) do
  {:ok, answer, _run} ->
    IO.puts("\n" <> String.duplicate("=", 70))
    sources = Tools.KnowledgeBase.sources_seen(source_agent)

    IO.puts(
      "Retrieved from: #{if sources == [], do: "(nothing)", else: Enum.join(sources, ", ")}"
    )

    IO.puts("\nFINAL ANSWER: #{answer}")
    IO.puts(String.duplicate("=", 70))

  {:error, reason, run} ->
    IO.puts("\nAgent run failed: #{inspect(reason)}")
    IO.puts("Steps so far:")
    Enum.each(run.steps, &IO.puts("  " <> Step.describe(&1)))
end
