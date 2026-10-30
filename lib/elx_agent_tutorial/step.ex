defmodule ElxAgentTutorial.Step do
  @moduledoc """
  One step of an agent run - the structured transcript entry every module
  after Module 3 inspects instead of scrolling a printed trace:
  `step_number`, `usage`, `duration_ms`, `error`, plus either `tool_calls`
  (`ToolCallingAgent`) or `code` (`CodeAgent`).
  """

  defstruct [
    :step_number,
    :tool_calls,
    :code,
    :observation,
    :error,
    :usage,
    :duration_ms
  ]

  @type t :: %__MODULE__{
          step_number: pos_integer(),
          tool_calls: [%{name: String.t(), input: map(), result: String.t()}] | nil,
          code: String.t() | nil,
          observation: String.t() | nil,
          error: String.t() | nil,
          usage: ElxAgentTutorial.Model.Usage.t(),
          duration_ms: non_neg_integer()
        }

  @doc """
  A one-line human-readable summary of what a step did, including its error
  if it had one. Meant for printing a run's `steps` list when a run fails -
  `{:error, reason, run}` on its own only tells you *that* it failed
  (`:max_steps_exceeded`, an HTTP error, ...), not what the agent was
  actually doing at each step along the way.
  """
  def describe(%__MODULE__{} = step) do
    action =
      cond do
        step.code not in [nil, ""] ->
          code = step.code |> to_string() |> String.replace("\n", " ; ")
          "wrote code: #{String.slice(code, 0, 100)}"

        step.tool_calls not in [nil, []] ->
          Enum.map_join(step.tool_calls, ", ", &"#{&1.name}(#{inspect(&1.input)})")

        true ->
          "(no action)"
      end

    error = if step.error, do: "  <- ERROR: #{step.error}", else: ""

    "step #{step.step_number}: #{action}#{error}"
  end
end
