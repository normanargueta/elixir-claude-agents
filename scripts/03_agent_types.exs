# Module 3 - ToolCallingAgent vs CodeAgent
# ========================================
#
# This tutorial ships two agent styles:
#
#   ToolCallingAgent  - the model emits Anthropic's native JSON tool call
#                       (one tool, one step). Good for simple, discrete
#                       actions.
#
#   CodeAgent         - the model writes a snippet of Elixir; calling a tool
#                       is a function call, so the model can chain several
#                       tool calls with logic between them in a single step.
#                       Good when a task needs computation or data wrangling.
#
# This module runs the SAME task through both, then prints a step-by-step
# summary of each so you can compare HOW the work happened:
#
#   * the CodeAgent tends to combine the lookup, the arithmetic and the final
#     answer into a few Elixir steps you can read: `usd = eur * rate`.
#   * the ToolCallingAgent takes one step per action - call a tool, observe,
#     call the next - and does any arithmetic inside its own reply text,
#     where you can't see or verify it.
#
# `:allowed_modules` only affects the CodeAgent, since the ToolCallingAgent
# has no interpreter to authorize modules into. `Code.eval_string/2` runs IN
# THIS PROCESS - fine for a trusted tutorial, but for untrusted input you'd
# want to isolate it in a separate OS process or container instead.
#
# Run it:
#     mix run scripts/03_agent_types.exs

alias ElxAgentTutorial.{CodeAgent, ToolCallingAgent, Tools}

task =
  "Look up today's EUR-to-USD exchange rate. Using that one rate, convert " <>
    "4000 euros to US dollars, and separately convert 4000 US dollars to " <>
    "euros. Show the rate and both results."

code_agent =
  CodeAgent.new(
    tools: [Tools.WebSearch.to_tool()],
    max_steps: 8
  )

tool_calling_agent = ToolCallingAgent.new(tools: [Tools.WebSearch.to_tool()], max_steps: 8)

summarize_code = fn steps, label ->
  IO.puts("\n#{label} - #{length(steps)} action step(s):")

  Enum.each(steps, fn step ->
    code =
      step.code
      |> to_string()
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ; ")

    IO.puts("  step #{step.step_number}  wrote code:  #{String.slice(code, 0, 95)}")
  end)
end

summarize_tools = fn steps, label ->
  IO.puts("\n#{label} - #{length(steps)} action step(s):")

  Enum.each(steps, fn step ->
    Enum.each(step.tool_calls || [], fn call ->
      IO.puts("  step #{step.step_number}  tool call:   #{call.name}(#{inspect(call.input)})")
    end)
  end)
end

IO.puts("Task: #{task}\n")
IO.puts("Running CodeAgent...")
{code_status, code_answer, code_run} = CodeAgent.run(code_agent, task)
IO.puts("Running ToolCallingAgent...")
{tc_status, json_answer, tc_run} = ToolCallingAgent.run(tool_calling_agent, task)

summarize_code.(code_run.steps, "CodeAgent")
summarize_tools.(tc_run.steps, "ToolCallingAgent")

format_result = fn
  :ok, answer -> answer
  :error, reason -> "(run failed: #{inspect(reason)} - see the step summary above for why)"
end

IO.puts("\n" <> String.duplicate("=", 70))
IO.puts("CodeAgent answer:\n  #{format_result.(code_status, code_answer)}")
IO.puts("\nToolCallingAgent answer:\n  #{format_result.(tc_status, json_answer)}")
IO.puts(String.duplicate("=", 70))
