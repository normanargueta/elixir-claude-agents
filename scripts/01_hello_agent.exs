# Module 1 - Your first agent
# ===========================
#
# An *agent* is an LLM running in a loop:
#
#     THINK  -> decide what to do next, given the goal and what you know so far
#     ACT    -> run a tool (search the web, run code, call an API...)
#     OBSERVE-> read the tool's result
#     ...repeat until the goal is met, then give a FINAL ANSWER.
#
# That loop is the entire idea. Everything else is plumbing.
#
# `ElxAgentTutorial.ToolCallingAgent` drives that loop with Anthropic's native
# JSON tool-calling: on each turn Claude either calls a tool or calls
# `final_answer` to end the run (see `lib/elx_agent_tutorial/tool_calling_agent.ex`
# - the core of the whole thing, worth reading once).
#
# Run it:
#     mix run scripts/01_hello_agent.exs

alias ElxAgentTutorial.{Step, ToolCallingAgent, Tools}

# Deliberately something the model can't answer from memory: the latest
# release of a fast-moving library, plus a comparison it must reason out from
# what the search returns. The tool has to do the work.
question =
  "What is the latest released version of the `phoenix` Elixir framework " <>
    "on Hex? Also say whether that release is newer than version 1.7.0."

agent =
  ToolCallingAgent.new(
    tools: [Tools.WebSearch.to_tool()],
    max_steps: 6
  )

IO.puts("Question: #{question}\n")
IO.puts("Running the agent...\n")

case ToolCallingAgent.run(agent, question) do
  {:ok, answer, _run} ->
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("FINAL ANSWER: #{answer}")
    IO.puts(String.duplicate("=", 70))

  {:error, reason, run} ->
    IO.puts("\nAgent run failed: #{inspect(reason)}")
    IO.puts("Steps so far:")
    Enum.each(run.steps, &IO.puts("  " <> Step.describe(&1)))
end
