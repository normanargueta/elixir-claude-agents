# Module 5 - Multi-agent systems
# ==============================
#
# One agent with fifteen tools gets confused. A cleaner pattern: a MANAGER
# agent that delegates sub-tasks to specialist WORKER agents.
#
# `ToolCallingAgent.as_tool/1` makes a running agent callable by another
# agent: give the worker a `:name` and `:description`, wrap it, and the
# manager sees it as one more tool - "call `web_researcher` with a question,
# get back an answer."
#
# Why bother?
#   * Focus     - each agent has a small, relevant toolset and prompt.
#   * Isolation - the worker's long transcript never pollutes the manager's
#                 context; only the final answer comes back.
#   * Cost      - fewer tokens carried around per step (but more LLM calls
#                 total, so it's a trade-off, not a free win).
#
# Here: a manager with NO tools of its own delegates every lookup to a web
# researcher, then does the comparison itself.
#
# Run it:
#     mix run scripts/05_multi_agent.exs

alias ElxAgentTutorial.{Step, ToolCallingAgent, Tools}

# Current GitHub star counts - the model cannot know these from memory, so
# each one is a real delegated lookup, and the manager does the ranking.
question =
  "Which of these GitHub repositories has the most stars right now: " <>
    "pytorch/pytorch, huggingface/transformers, or langchain-ai/langchain? " <>
    "Give the current star count for each and name the leader."

web_researcher =
  ToolCallingAgent.new(
    tools: [Tools.WebSearch.to_tool(), Tools.VisitWebpage.to_tool()],
    max_steps: 8,
    name: "web_researcher",
    description:
      "Answers a single factual question by searching the web and reading pages. " <>
        "Give it ONE clear, self-contained question and it returns a short factual answer."
  )

{web_researcher_tool, worker_last_run} = ToolCallingAgent.as_tool(web_researcher)

manager =
  ToolCallingAgent.new(
    # the manager itself has no tools of its own besides the delegated worker
    tools: [web_researcher_tool],
    max_steps: 8
  )

IO.puts("Question: #{question}\n")
IO.puts("Running the manager (it will delegate to the web_researcher worker)...\n")

{status, answer_or_reason, run} = ToolCallingAgent.run(manager, question)

delegations =
  Enum.count(run.steps, fn step ->
    Enum.any?(step.tool_calls || [], &(&1.name == "web_researcher"))
  end)

worker_steps =
  case worker_last_run.() do
    {_status, _answer, worker_run} -> length(worker_run.steps)
    nil -> 0
  end

IO.puts(String.duplicate("=", 70))

IO.puts(
  "manager: #{length(run.steps)} step(s), delegated to web_researcher #{delegations} time(s)"
)

IO.puts(
  "web_researcher: #{worker_steps} step(s) on its last call " <>
    "(its full transcript stayed out of the manager's context)"
)

case status do
  :ok ->
    IO.puts("\nFINAL ANSWER: #{answer_or_reason}")

  :error ->
    IO.puts("\nAgent run failed: #{inspect(answer_or_reason)}")
    IO.puts("Manager's steps:")
    Enum.each(run.steps, &IO.puts("  " <> Step.describe(&1)))
end

IO.puts(String.duplicate("=", 70))
