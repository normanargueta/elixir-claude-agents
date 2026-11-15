# Capstone - ask the Research Assistant one question from the terminal.
#
# The reusable agent logic lives in `ElxAgentTutorial.Capstone`
# (lib/elx_agent_tutorial/capstone.ex) - this script is just the CLI entry
# point. `capstone/app.exs` is the web entry point.
#
# Run it:
#     mix run capstone/agent.exs "your question here"

alias ElxAgentTutorial.{Capstone, Step, ToolCallingAgent}

question =
  case System.argv() do
    [] ->
      "What is the Pro plan's monthly event quota, and how does that compare " <>
        "to what a typical analytics startup needs today?"

    args ->
      Enum.join(args, " ")
  end

IO.puts("Question: #{question}\n")
IO.puts("Researching (this can take 30-60s and several steps)...\n")

case ToolCallingAgent.run(Capstone.build_agent(), question) do
  {:ok, answer, _run} ->
    IO.puts(answer)

  {:error, reason, run} ->
    IO.puts("Agent run failed: #{inspect(reason)}")
    IO.puts("Steps so far:")
    Enum.each(run.steps, &IO.puts("  " <> Step.describe(&1)))
end
