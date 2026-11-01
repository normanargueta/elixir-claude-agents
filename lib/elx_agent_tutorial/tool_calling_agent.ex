defmodule ElxAgentTutorial.ToolCallingAgent do
  @moduledoc """
  The agent loop - THINK (call Claude) -> ACT (run a tool) -> OBSERVE (feed the
  result back) -> repeat until `final_answer` is called or `max_steps` runs out.

  The model emits a tool call (Anthropic's native JSON tool-use, not
  free-form text), the runtime executes it, the result goes back as a
  `tool_result` block. `ElxAgentTutorial.CodeAgent` (Module 3) is the other
  style - the model writes and runs Elixir instead.

  Kept deliberately small and free of abstraction: the point of this tutorial
  is to see the whole loop, not to hide it inside a framework.
  """

  alias ElxAgentTutorial.{Model, Step, Tool}
  alias ElxAgentTutorial.Model.Usage

  @enforce_keys [:tools]
  defstruct tools: [],
            instructions: nil,
            max_steps: 10,
            planning_intervals: nil,
            step_callbacks: [],
            name: nil,
            description: nil

  @type t :: %__MODULE__{}

  @default_instructions """
  You are a helpful agent that solves tasks by calling tools. Work step by \
  step: call one or more tools, read the results, and keep going until you \
  can answer. When you have arrived at the final answer, call the \
  `final_answer` tool with the complete answer text as its `answer` \
  argument - never give the final answer as plain text.
  """

  def new(opts) do
    struct!(__MODULE__, opts)
  end

  @doc """
  Run the agent on a task. Returns `{:ok, answer, run}` or
  `{:error, reason, run}`, where `run` is `%{steps: [%Step{}, ...], usage:
  %Usage{}}` - the full structured transcript plus running token totals
  (see Module 8).
  """
  def run(%__MODULE__{} = agent, task) when is_binary(task) do
    tools = agent.tools ++ [final_answer_tool()]
    tools_by_name = Map.new(tools, &{&1.name, &1})
    anthropic_tools = Enum.map(tools, &Tool.to_anthropic_schema/1)
    system = agent.instructions || @default_instructions

    loop(
      agent,
      tools_by_name,
      anthropic_tools,
      system,
      [%{"role" => "user", "content" => task}],
      1,
      [],
      %Usage{}
    )
  end

  defp final_answer_tool do
    Tool.from_fun(
      "final_answer",
      "Call this with your complete final answer once you have enough information to answer the task. This ends the run.",
      %{"answer" => %{type: "string", doc: "The final answer to give the user."}},
      fn %{"answer" => answer} -> answer end
    )
  end

  defp loop(
         agent,
         _tools_by_name,
         _anthropic_tools,
         _system,
         _messages,
         step_number,
         steps,
         usage
       )
       when step_number > agent.max_steps do
    {:error, :max_steps_exceeded, %{steps: Enum.reverse(steps), usage: usage}}
  end

  defp loop(agent, tools_by_name, anthropic_tools, system, messages, step_number, steps, usage) do
    messages = maybe_replan(agent, messages, step_number)
    t0 = System.monotonic_time(:millisecond)

    case Model.chat(messages, system: system, tools: anthropic_tools) do
      {:ok, resp} ->
        usage = Usage.add(usage, resp.usage)
        duration_ms = System.monotonic_time(:millisecond) - t0

        case(find_final_answer(resp.tool_calls)) do
          {:ok, answer} ->
            step = %Step{
              step_number: step_number,
              tool_calls: [%{name: "final_answer", input: %{"answer" => answer}, result: answer}],
              usage: resp.usage,
              duration_ms: duration_ms
            }

            steps = [step | steps]
            emit(agent, step, %{name: agent.name})
            {:ok, answer, %{steps: Enum.reverse(steps), usage: usage}}

          :not_found ->
            step_and_continue(
              agent,
              tools_by_name,
              anthropic_tools,
              system,
              messages,
              resp,
              step_number,
              steps,
              usage,
              duration_ms
            )
        end

      {:error, reason} ->
        {:error, reason, %{steps: Enum.reverse(steps), usage: usage}}
    end
  end

  defp maybe_replan(%{planning_interval: n}, messages, step_number)
       when is_integer(n) and n > 0 and step_number > 1 and rem(step_number - 1, n) == 0 do
    messages ++
      [
        %{
          "role" => "user",
          "content" =>
            "(Planning checkpoint) Pause and reconsider: given progress so far, " <>
              "is your current approach still the best path to the answer? Adjust if not, then continue."
        }
      ]
  end

  defp maybe_replan(_agent, messages, _step_number), do: messages

  defp find_final_answer(tool_calls) do
    case Enum.find(tool_calls, &(&1["name"] == "final_answer")) do
      nil -> :not_found
      %{"input" => %{"answer" => answer}} -> {:ok, answer}
      %{"input" => input} -> {:ok, Jason.encode!(input)}
    end
  end

  defp emit(agent, %Step{} = step, metadata) do
    :telemetry.execute(
      [:elx_agent_tutorial, :agent, :step],
      %{tokens: Usage.total(step.usage), duration_ms: step.duration_ms},
      Map.put(metadata, :step, step)
    )

    Enum.each(agent.step_callbacks, & &1.(step))
  end

  defp step_and_continue(
         agent,
         tools_by_name,
         anthropic_tools,
         system,
         messages,
         resp,
         step_number,
         steps,
         usage,
         duration_ms
       ) do
    if resp.tool_calls == [] do
      # No tool call and no final_answer - treat the plain text as the answer
      # rather than looping forever (a defensive fallback; well-behaved runs
      # always end via final_answer).
      step = %Step{
        step_number: step_number,
        tool_calls: [],
        usage: resp.usage,
        duration_ms: duration_ms
      }

      {:ok, resp.text || "", %{steps: Enum.reverse([step | steps]), usage: usage}}
    else
      {calls, results} = execute_tools(resp.tool_calls, tools_by_name)

      error = Enum.find_value(results, fn r -> if r.is_error, do: r.content end)

      step = %Step{
        step_number: step_number,
        tool_calls: calls,
        error: error,
        usage: resp.usage,
        duration_ms: duration_ms
      }

      steps = [step | steps]

      emit(agent, step, %{name: agent.name})

      assistant_msg = %{"role" => "assistant", "content" => resp.content}
      tool_result_msg = %{"role" => "user", "content" => Enum.map(results, &tool_result_block/1)}

      loop(
        agent,
        tools_by_name,
        anthropic_tools,
        system,
        messages ++ [assistant_msg, tool_result_msg],
        step_number + 1,
        steps,
        usage
      )
    end
  end

  defp execute_tools(tool_calls, tools_by_name) do
    Enum.map(tool_calls, fn %{"id" => id, "name" => name, "input" => input} ->
      case Map.fetch(tools_by_name, name) do
        {:ok, tool} ->
          case Tool.call(tool, input) do
            {:ok, result} ->
              {%{name: name, input: input, result: result},
               %{id: id, content: result, is_error: false}}

            {:error, message} ->
              {%{name: name, input: input, result: message},
               %{id: id, content: message, is_error: true}}
          end

        :error ->
          message = "Unknown tool: #{name}"

          {%{name: name, input: input, result: message},
           %{id: id, content: message, is_error: true}}
      end
    end)
    |> Enum.unzip()
  end

  defp tool_result_block(%{id: id, content: content, is_error: is_error}) do
    %{"type" => "tool_result", "tool_use_id" => id, "content" => content, "is_error" => is_error}
  end
end
