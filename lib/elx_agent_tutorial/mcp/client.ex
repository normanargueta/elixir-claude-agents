defmodule ElxAgentTutorial.MCP.Client do
  @moduledoc """
  Module 6, client side. `with_tools/3` spawns an MCP server as a subprocess
  (an Erlang `Port`, line-framed so every message from the port arrives as one
  Elixir message - no manual buffering needed), does the `initialize` /
  `tools/list` handshake, wraps each remote tool as a normal `%Tool{}` whose
  `forward` sends a `tools/call` request, hands the list to your function, and
  stops the subprocess when it returns - the tools are live only for the
  duration of `fun`.

  The port is owned by a small dedicated process (`owner_loop/1`), not by
  whichever process calls `with_tools/3`. That matters because a `Port`'s
  replies are delivered only to the process that opened it - if `CodeAgent`'s
  sandbox (which runs each step's generated code inside its own `Task`) called
  the port directly, the reply would land in the wrong process's mailbox and
  every call would time out. Routing every request through the owner process
  via plain Elixir messages - safe to send from any process - sidesteps that
  entirely; only the owner process ever touches the port itself.
  """

  alias ElxAgentTutorial.Tool

  @protocol_version "2024-11-05"
  @request_timeout 15_000

  @doc """
  Run `fun.(tools)` with `tools` loaded from the MCP server started by
  `cmd args...` (e.g. `with_tools("mix", ["run", "scripts/mcp_server_example.exs"], fun)`).
  """
  def with_tools(cmd, args, fun) do
    executable = System.find_executable(cmd) || raise "executable not found: #{cmd}"
    owner = spawn_owner(executable, args)

    try do
      {:ok, _init} =
        call(owner, "initialize", %{
          "protocolVersion" => @protocol_version,
          "capabilities" => %{},
          "clientInfo" => %{"name" => "elx-agent-tutorial", "version" => "0.1.0"}
        })

      notify(owner, "notifications/initialized", %{})
      {:ok, %{"tools" => raw_tools}} = call(owner, "tools/list", %{})
      fun.(Enum.map(raw_tools, &to_tool(&1, owner)))
    after
      send(owner, :stop)
    end
  end

  defp to_tool(%{"name" => name} = raw, owner) do
    schema = raw["inputSchema"] || %{}

    inputs =
      Map.new(schema["properties"] || %{}, fn {key, spec} ->
        {key, %{type: spec["type"] || "string", doc: spec["description"] || ""}}
      end)

    Tool.from_fun(name, raw["description"] || "", inputs, fn args ->
      call_remote(owner, name, args)
    end)
  end

  defp call_remote(owner, name, args) do
    case call(owner, "tools/call", %{"name" => name, "arguments" => args}) do
      {:ok, %{"content" => content}} -> Enum.map_join(content, "\n", & &1["text"])
      {:ok, other} -> inspect(other)
      {:error, message} -> raise message
    end
  end

  # --- the owner process ------------------------------------------------
  #
  # Opens the port and is the only process that ever calls Port.command/2 or
  # receives {port, ...} messages. Every other process (the caller of
  # with_tools/3, and any Task a sandboxed CodeAgent step spawns) talks to it
  # with plain `send`/`receive`, which works from anywhere.
  defp spawn_owner(executable, args) do
    spawn_link(fn ->
      port =
        Port.open({:spawn_executable, executable}, [
          :binary,
          :exit_status,
          {:line, 1_000_000},
          args: args
        ])

      owner_loop(port)
    end)
  end

  defp owner_loop(port) do
    receive do
      {:call, from, ref, method, params} ->
        id = System.unique_integer([:positive])
        send_json(port, %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params})
        send(from, {ref, await_reply(port, id)})
        owner_loop(port)

      {:notify, method, params} ->
        send_json(port, %{"jsonrpc" => "2.0", "method" => method, "params" => params})
        owner_loop(port)

      :stop ->
        if Port.info(port), do: Port.close(port)

      {^port, {:exit_status, _status}} ->
        :ok
    end
  end

  defp call(owner, method, params) do
    ref = make_ref()
    send(owner, {:call, self(), ref, method, params})

    receive do
      {^ref, result} -> result
    after
      @request_timeout -> {:error, "MCP request timed out after #{@request_timeout}ms"}
    end
  end

  defp notify(owner, method, params), do: send(owner, {:notify, method, params})

  defp send_json(port, message), do: Port.command(port, Jason.encode!(message) <> "\n")

  defp await_reply(port, id) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        case Jason.decode!(line) do
          %{"id" => ^id, "result" => result} -> {:ok, result}
          %{"id" => ^id, "error" => error} -> {:error, error["message"] || "MCP error"}
          # Not the reply we're waiting for (e.g. a notification) - keep reading.
          _other -> await_reply(port, id)
        end

      {^port, {:exit_status, status}} ->
        {:error, "MCP server exited with status #{status}"}
    after
      @request_timeout -> {:error, "MCP request timed out after #{@request_timeout}ms"}
    end
  end
end
