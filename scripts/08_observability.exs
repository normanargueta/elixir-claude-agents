# Module 8 - Seeing what your agent did (and what it cost)
# =========================================================
#
# Agents fail in ways plain functions don't: wrong tool, looping, a tool that
# errors, an answer that ignores the evidence. You need visibility.
#
# Three mechanisms, shown here:
#
#   1. `:step_callbacks` - functions called after every step (an option on
#      both ToolCallingAgent and CodeAgent). Use them for custom logging,
#      metrics, tripwires ("stop if it visits the same URL twice").
#   2. the `run.steps` list  - the full structured transcript after a run:
#      every step, its tool calls or code, any error, per-step token usage.
#   3. `:telemetry`     - every step also fires a
#      `[:elx_agent_tutorial, :agent, :step]` event, independent of the
#      caller. `ElxAgentTutorial.Telemetry.with_totals/1` uses it to
#      accumulate running totals: the standard event bus every serious
#      Elixir app already uses, and the natural place to plug in an
#      OpenTelemetry exporter for a real deployment.
#
# `max_steps` is your hard stop against runaway loops - always set it in
# production.
#
# This uses CodeAgent rather than ToolCallingAgent, and deliberately so: "how
# many days ago" needs today's date and a subtraction, and a ToolCallingAgent
# has no way to get either short of an unreliable web search for "today's
# date." CodeAgent can just call `Date.utc_today/0` and `Date.diff/2` in the
# code it writes - real, checkable arithmetic instead of a guess buried in
# reply text (the same lesson Module 3 makes about the two agent styles).
#
# Run it:
#     mix run scripts/08_observability.exs

alias ElxAgentTutorial.{CodeAgent, Model, Step, Telemetry, Tools}

question =
  "What is the latest stable version of Python 3, and on what date was it " <>
    "released? Then compute how many days ago that was."

log_step = fn step ->
  tokens = Model.Usage.total(step.usage)
  duration = Float.round(step.duration_ms / 1000, 1)
  error = if step.error, do: "\n     ERROR: #{step.error}", else: ""
  IO.puts("  >> step #{step.step_number}: #{tokens} tokens, #{duration}s#{error}")
end

agent =
  CodeAgent.new(
    tools: [Tools.WebSearch.to_tool()],
    allowed_modules: [Enum, String, Integer, Float, Kernel, IO, Date],
    max_steps: 5,
    # our hook, called after every step
    step_callbacks: [log_step]
  )

IO.puts("Question: #{question}\n")

# Independently of step_callbacks, every step also fires a :telemetry event -
# with_totals/1 attaches a temporary handler to accumulate token totals from
# that event stream, the way you'd wire up billing/usage dashboards for real.
{result, totals} = Telemetry.with_totals(fn -> CodeAgent.run(agent, question) end)

case result do
  {:ok, answer, run} ->
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("FINAL ANSWER: #{answer}")
    IO.puts(String.duplicate("=", 70))

    IO.puts("\nThe agent took #{length(run.steps)} action step(s):")
    Enum.each(run.steps, &IO.puts("  " <> Step.describe(&1)))

    # --- totals: this is what you get billed for ---------------------------
    IO.puts(
      "\nToken usage - input: #{totals.input_tokens}, output: #{totals.output_tokens}, " <>
        "total: #{Model.Usage.total(totals)}"
    )

    IO.puts(
      "Approx cost of this run at Sonnet list price: $#{:erlang.float_to_binary(Model.Usage.cost(totals), decimals: 4)}"
    )

  {:error, reason, run} ->
    IO.puts("\nAgent run failed: #{inspect(reason)}")
    IO.puts("Steps so far:")
    Enum.each(run.steps, &IO.puts("  " <> Step.describe(&1)))
end
