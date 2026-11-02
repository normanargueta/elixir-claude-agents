# Module 2 - Writing your own tools
# =================================
#
# A tool is just a function the agent is allowed to call.
# `ElxAgentTutorial.Tool` needs three things from every tool:
#
#   * a NAME               -> how the model refers to it
#   * a DESCRIPTION + typed INPUTS -> so the model knows when and how to use it
#   * the CODE to run
#
# `use ElxAgentTutorial.Tool` builds all of that from a module's `name/0`,
# `description/0`, `inputs/0` and `forward/1` - see
# `lib/elx_agent_tutorial/tools/weather.ex`. The description and each input's
# `doc:` are not comments for humans - they are the contract the model reads,
# so get them right.
#
# This module gives the agent two tools and a task that needs both:
#   1. `Tools.WebSearch` (from Module 1) - to look up a city's coordinates
#   2. `Tools.Weather`   (new here)      - to fetch live weather for those coordinates
#
# Run it:
#     mix run scripts/02_custom_tools.exs

alias ElxAgentTutorial.{Step, ToolCallingAgent, Tools}

# Tuktoyaktuk is obscure enough that the model has to search for its
# coordinates rather than recall them - so the run genuinely uses both tools:
# web search to geolocate, then the weather tool.
question =
  "What is the weather like right now in Tuktoyaktuk, Canada? " <>
    "First find its latitude and longitude, then check the weather."

tools = [Tools.WebSearch.to_tool(), Tools.Weather.to_tool()]
agent = ToolCallingAgent.new(tools: tools, max_steps: 8)

IO.puts("Question: #{question}")
# final_answer is always in the tool list - the loop adds it so the agent has
# a way to end the run (see ToolCallingAgent.run/2).
IO.puts("Tools available: #{inspect(Enum.map(tools, & &1.name) ++ ["final_answer"])}\n")

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
