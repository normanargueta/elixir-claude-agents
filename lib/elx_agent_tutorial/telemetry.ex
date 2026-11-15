defmodule ElxAgentTutorial.Telemetry do
  @moduledoc """
  Module 8 - seeing what your agent did.

  `ElxAgentTutorial.ToolCallingAgent` and `CodeAgent` give you two pieces of
  visibility directly: a `:step_callbacks` option (functions called after
  every step) and the `run` map's `:steps` list (the full structured
  transcript). The third idea - "a running total the whole system can
  observe without the caller wiring it through" - is exactly what
  `:telemetry` is for in the Elixir ecosystem: it ships with the runtime,
  every serious Elixir library already emits it, and attaching a handler
  costs one function call. Both agents call
  `:telemetry.execute([:elx_agent_tutorial, :agent, :step], measurements,
  metadata)` after every step, whether or not anyone is listening.

  `attach_logger/0` prints a `>> step N: ...` line per step; `with_totals/1`
  accumulates running token totals from that same event stream.
  """
  alias ElxAgentTutorial.Model.Usage

  @event [:elx_agent_tutorial, :agent, :step]

  @doc "Print one `>> step N: ...` line per step as it happens."
  def attach_logger(handler_id \\ __MODULE__) do
    :telemetry.attach(
      handler_id,
      @event,
      fn @event, %{tokens: tokens, duration_ms: duration_ms}, %{step: step}, _config ->
        error = if step.error, do: "\n     ERROR: #{step.error}", else: ""

        IO.puts(
          "  >> step #{step.step_number}: #{tokens} tokens, #{Float.round(duration_ms / 1000, 1)}s#{error}"
        )
      end,
      nil
    )

    handler_id
  end

  def detach(handler_id), do: :telemetry.detach(handler_id)

  @doc """
  Run `fun.()` (expected to call `ToolCallingAgent.run/2` or `CodeAgent.run/2`
  and return its `{:ok | :error, answer, run}` result) while accumulating
  every step's token usage via a temporary telemetry handler, independent of
  whatever `run.usage` the agent itself returns. Returns `{result, totals}`.
  """
  def with_totals(fun) do
    {:ok, agent_pid} = Agent.start_link(fn -> %Usage{} end)
    handler_id = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler_id,
      @event,
      fn @event, _measurements, %{step: step}, _config ->
        Agent.update(agent_pid, &Usage.add(&1, step.usage))
      end,
      nil
    )

    result = fun.()
    totals = Agent.get(agent_pid, & &1)
    :telemetry.detach(handler_id)
    Agent.stop(agent_pid)
    {result, totals}
  end
end
