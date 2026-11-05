defmodule ElxAgentTutorial.CodeAgent do
  @moduledoc """
  Module 3's other agent style: instead of emitting a JSON tool call, the
  model writes a snippet of **Elixir** and we `Code.eval_string/2` it, with
  every tool bound as a local function. Calling a tool is then just a
  function call, so the model can combine tools with variables, pattern
  matching and pipes in one step - fewer steps, often, than one tool call
  per turn.

  Compare this module's step summaries against `ToolCallingAgent`'s (Module 3
  prints both): every step here is "wrote code"; every step there is a single
  "tool call" whose arguments and any arithmetic sit inside a JSON blob you
  can't verify without re-deriving it yourself.

  ## Sandboxing

  `Code.eval_string/2` runs in THIS process, with the same privileges as the
  rest of the app - fine for a trusted tutorial, not fine for untrusted input.
  Two guards are applied before anything is evaluated:

    * an **allowlist** of modules the generated code may reference
      (`:allowed_modules`, e.g. `[Enum, String, Integer]`); anything outside
      it is rejected by inspecting the parsed AST before eval, never by
      trying to catch it at runtime. `IO` is allowed by default - the model
      often reaches for `IO.puts`/`IO.inspect` out of habit to "see" a value,
      and printing to stdout has no file/network/process access to worry
      about, unlike everything else this allowlist exists to keep out.
    * a hard **timeout**, running the eval in a supervised `Task` so an
      infinite loop can't hang the agent. `:eval_timeout_ms` defaults to
      60s, not something short like 5s, because the code being timed
      isn't just local computation - a tool call in that code can itself be
      a nested network call (e.g. `Tools.WebSearch` makes its own Anthropic
      API call with server-side search, which can legitimately take tens of
      seconds). Too short a timeout doesn't just fail a step cleanly: killing
      an in-flight HTTP request in a `Task.shutdown(:brutal_kill)` and
      immediately firing another one right behind it is exactly the kind of
      pattern that exhausts an HTTP connection pool - give slow tools enough
      room instead of racing them.

  For real untrusted input, don't rely on the in-process default: run this in
  an isolated OS process or container instead.
  """

  alias ElxAgentTutorial.{Model, Step, Tool}
  alias ElxAgentTutorial.Model.Usage

  @enforce_keys [:tools]
  defstruct tools: [],
            instructions: nil,
            max_steps: 10,
            allowed_modules: [Enum, String, Integer, Float, Kernel, IO],
            eval_timeout_ms: 60_000,
            step_callbacks: []

  @code_fence ~r/```(?:elixir)?\s*\n(.*?)```/s
  @always_allowed [:final_answer]

  def new(opts), do: struct!(__MODULE__, opts)

  def run(%__MODULE__{} = agent, task) when is_binary(task) do
    system = system_prompt(agent)
    messages = [%{"role" => "user", "content" => task}]
    loop(agent, system, messages, 1, [], %Usage{}, %{})
  end

  defp system_prompt(agent) do
    tool_docs =
      Enum.map_join(agent.tools, "\n\n", fn %Tool{
                                              name: name,
                                              description: description,
                                              inputs: inputs
                                            } ->
        args = inputs |> Map.keys() |> Enum.map_join(", ", &"#{&1}: ...") |> then(&"%{#{&1}}")
        # `name` is bound as a local variable holding a function, so calling it
        # needs the anonymous-function dot: `name.(args)`, not `name(args)`
        # (which would instead look for an undefined function `name/1`).
        "* #{name}.(#{args}) - #{description}"
      end)

    base = """
    You are a helpful agent that solves tasks by writing and running Elixir code.

    On every turn, respond with EXACTLY ONE fenced ```elixir code block and nothing
    else meaningful outside it. The code may use these functions, each taking a
    single map of named arguments and returning a string:

    #{tool_docs}

    Call `final_answer.(answer)` with your complete answer once you have enough
    information - this ends the run. Variables you bind persist to your next turn.
    You'll be shown the result of your code (or an error) as "Out: ..." - read it
    before writing the next step. You do not need to print anything yourself
    (with IO.puts, IO.inspect, or otherwise) to see a value - just leave it as
    the last expression in your code and it will be shown to you the same way.
    Allowed modules besides your bound functions:
    #{Enum.map_join(agent.allowed_modules, ", ", &inspect/1)}.
    """

    if agent.instructions, do: agent.instructions <> "\n\n" <> base, else: base
  end

  defp loop(agent, _system, _messages, step_number, steps, usage, _bindings)
       when step_number > agent.max_steps do
    {:error, :max_steps_exceeded, %{steps: Enum.reverse(steps), usage: usage}}
  end

  defp loop(agent, system, messages, step_number, steps, usage, bindings) do
    t0 = System.monotonic_time(:millisecond)

    case Model.chat(messages, system: system) do
      {:ok, resp} ->
        usage = Usage.add(usage, resp.usage)
        duration_ms = System.monotonic_time(:millisecond) - t0
        code = extract_code(resp.text)

        run_step(
          agent,
          system,
          messages,
          resp,
          code,
          step_number,
          steps,
          usage,
          duration_ms,
          bindings
        )
    end
  end

  defp extract_code(nil), do: nil

  defp extract_code(text) do
    case Regex.run(@code_fence, text) do
      [_, code] -> String.trim(code)
      nil -> nil
    end
  end

  defp run_step(
         _agent,
         _system,
         _messages,
         resp,
         nil,
         step_number,
         steps,
         usage,
         duration_ms,
         _bindings
       ) do
    # The model didn't write a code block - treat its text as the answer
    # rather than looping forever.
    step = %Step{
      step_number: step_number,
      code: nil,
      observation: resp.text,
      usage: resp.usage,
      duration_ms: duration_ms
    }

    {:ok, resp.text || "", %{steps: Enum.reverse([step | steps]), usage: usage}}
  end

  defp run_step(
         agent,
         system,
         messages,
         resp,
         code,
         step_number,
         steps,
         usage,
         duration_ms,
         bindings
       ) do
    case eval_code(agent, code, bindings) do
      {:final_answer, answer, _bindings} ->
        step = %Step{
          step_number: step_number,
          code: code,
          observation: "final_answer(...)",
          usage: resp.usage,
          duration_ms: duration_ms
        }

        steps = [step | steps]
        emit(agent, step)

        {:ok, to_string(answer), %{steps: Enum.reverse(steps), usage: usage}}

      {:ok, result, new_bindings} ->
        observation = "Out: #{inspect(result)}"

        step = %Step{
          step_number: step_number,
          code: code,
          observation: observation,
          usage: resp.usage,
          duration_ms: duration_ms
        }

        steps = [step | steps]

        emit(agent, step)

        continue(
          agent,
          system,
          messages,
          code,
          observation,
          step_number,
          steps,
          usage,
          new_bindings
        )

      {:error, message} ->
        observation = "Error: #{message}"

        step = %Step{
          step_number: step_number,
          code: code,
          observation: observation,
          error: message,
          usage: resp.usage,
          duration_ms: duration_ms
        }

        steps = [step | steps]
        emit(agent, step)
        continue(agent, system, messages, code, observation, step_number, steps, usage, bindings)
    end
  end

  defp eval_code(agent, code, bindings) do
    with :ok <- check_ast(agent, code) do
      task_bindings = tool_bindings(agent) ++ Enum.into(bindings, [])

      task =
        Task.async(fn ->
          try do
            {result, new_bindings} = Code.eval_string(code, task_bindings)
            {:ok, result, drop_tools(agent, new_bindings)}
          rescue
            e -> {:error, Exception.format(:error, e, __STACKTRACE__)}
          catch
            {:final_answer, answer} -> {:final_answer, answer, bindings}
          end
        end)

      case Task.yield(task, agent.eval_timeout_ms) || Task.shutdown(task, :brutal_kill) do
        {:ok, outcome} -> outcome
        nil -> {:error, "timed out after #{agent.eval_timeout_ms}ms"}
      end
    end
  end

  defp check_ast(agent, code) do
    case Code.string_to_quoted(code) do
      {:ok, ast} ->
        case forbidden_call(ast, agent.allowed_modules) do
          nil ->
            :ok

          call ->
            {:error,
             "not authorized to call #{call} (add it to :allowed_modules if you trust it)"}
        end

      {:error, {_meta, message, token}} ->
        {:error, "syntax error: #{inspect(message)} #{inspect(token)}"}
    end
  end

  defp forbidden_call(ast, allowed_modules) do
    {_ast, found} =
      Macro.prewalk(ast, nil, fn
        node, acc when not is_nil(acc) ->
          {node, acc}

        {{:., _, [{:__aliases__, _, mod_parts}, _fun]}, _, _} = node, nil ->
          # mod_parts is a list of atoms (e.g. [:Float]) - Module.concat/1
          # turns it back into the module atom (Float) so we can compare it
          # directly against :allowed_modules, itself a list of module atoms.
          module = Module.concat(mod_parts)
          if module in allowed_modules, do: {node, nil}, else: {node, inspect(module)}

        {{:., _, [module, fun]}, _, _} = node, nil when is_atom(module) ->
          # A bare-atom module reference (no `__aliases__` wrapper) shows up
          # two ways: a lowercase Erlang-style call written directly, e.g.
          # `:os.cmd(...)` - genuinely worth blocking - and, much more often,
          # something the *parser itself* generates from ordinary source: any
          # string interpolation ("...#{x}...") desugars at parse time into a
          # call to the bare atom `Kernel.to_string/1`, not to `Kernel` via
          # `__aliases__`. Blocking every bare-atom call unconditionally (as
          # this used to) therefore blocked string interpolation entirely -
          # check it against :allowed_modules like any other call instead.
          if module in allowed_modules or fun in @always_allowed do
            {node, nil}
          else
            {node, "#{inspect(module)}.#{fun}"}
          end

        {fun, _, args} = node, nil when is_atom(fun) and is_list(args) ->
          if fun in [:spawn, :spawn_link, :send, :receive] do
            {node, to_string(fun)}
          else
            {node, nil}
          end

        node, nil ->
          {node, nil}
      end)

    found
  end

  # Tools + final_answer are bound as local functions of one argument (a map
  # of named args), same call shape as the JSON tool schema they're derived
  # from - so a tool works identically whichever agent style calls it.
  defp tool_bindings(agent) do
    tool_funs =
      Enum.map(agent.tools, fn %Tool{name: name} = tool ->
        {String.to_atom(name), fn args -> elem(Tool.call(tool, stringify_keys(args)), 1) end}
      end)

    final_answer = fn answer -> throw({:final_answer, answer}) end
    [{:final_answer, final_answer} | tool_funs]
  end

  defp stringify_keys(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  defp drop_tools(agent, bindings) do
    tool_names = Enum.map(agent.tools, & &1.name) ++ ["final_answer"]
    reserved = Enum.map(tool_names, &String.to_atom/1)
    Enum.reject(bindings, fn {name, _} -> name in reserved end)
  end

  defp emit(agent, %Step{} = step) do
    :telemetry.execute(
      [:elx_agent_tutorial, :agent, :step],
      %{tokens: Usage.total(step.usage), duration_ms: step.duration_ms},
      %{step: step}
    )

    Enum.each(agent.step_callbacks, & &1.(step))
  end

  defp continue(agent, system, messages, code, observation, step_number, steps, usage, bindings) do
    messages =
      messages ++
        [
          %{"role" => "assistant", "content" => "```elixir\n#{code}\n```"},
          %{"role" => "user", "content" => observation}
        ]

    loop(agent, system, messages, step_number + 1, steps, usage, bindings)
  end
end
