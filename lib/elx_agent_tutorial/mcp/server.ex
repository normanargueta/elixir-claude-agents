defmodule ElxAgentTutorial.Mcp.Server do
  @moduledoc """
  Module 6 - a tiny [MCP](https://modelcontextprotocol.io) server over stdio.

  MCP is JSON-RPC 2.0, one message per line on stdin/stdout. At the level this
  tutorial needs - `initialize`, `tools/list`, `tools/call` - that's the whole
  protocol, so rather than reach for a churning third-party MCP dependency,
  this is about 60 lines of native Elixir: `IO.gets/2` to read a line,
  `Jason` to decode/encode it, `IO.puts/1` to reply. The point of Module 6:
  you don't have to write every tool, but you also don't need much code to
  *speak the protocol* that lets you load one.

  Give it a list of `%ElxAgentTutorial.Tool{}` and call `serve/2`. See
  `scripts/mcp_server_example.exs` for the two toy tools Module 6 loads, and
  `ElxAgentTutorial.MCP.Client` for the other end of the pipe.
  """

  alias ElxAgentTutorial.Tool

  @protocol_version "2024-11-05"

  @doc "Block forever, serving `tools` over stdio until stdin closes."
  def serve(tools, opts \\ []) do
    name = Keyword.get(opts, :name, "tutorial-tools")
    tools_by_name = Map.new(tools, &{&1.name, &1})
    loop(tools_by_name, name)
  end

  defp loop(tools_by_name, name) do
    case IO.gets(:stdio, "") do
      :eof ->
        :ok

      {:error, _reason} ->
        :ok

      line ->
        line |> String.trim() |> handle_line(tools_by_name, name)
        loop(tools_by_name, name)
    end
  end

  defp handle_line("", _tools, _name), do: :ok

  defp handle_line(line, tools_by_name, name) do
    case Jason.decode(line) do
      {:ok, message} -> handle_message(message, tools_by_name, name)
      {:error, _reason} -> :ok
    end
  end

  defp handle_message(%{"method" => "initialize", "id" => id}, _tools, name) do
    reply(id, %{
      "protocolVersion" => @protocol_version,
      "capabilities" => %{"tools" => %{}},
      "serverInfo" => %{"name" => name, "version" => "0.1.0"}
    })
  end

  defp handle_message(%{"method" => "notifications/" <> _}, _tools, _name), do: ok

  defp handle_message(%{"method" => "tools/list", "id" => id}, tools_by_name, _name) do
    tools =
      tools_by_name
      |> Map.values()
      |> Enum.map(fn t ->
        %{"name" => t.name, "description" => t.description, "inputSchema" => Tool.input_schema(t)}
      end)

    reply(id, %{"tools" => tools})
  end

  defp handle_message(
         %{"method" => "tools/call", "id" => id, "params" => %{"name" => name} = params},
         tools_by_name,
         _name
       ) do
    args = params["arguments"] || %{}

    case Map.fetch(tools_by_name, name) do
      {:ok, tool} ->
        case Tool.call(tool, args) do
          {:ok, result} ->
            reply(id, %{"content" => [%{"type" => "text", "text" => result}], "isError" => false})

          {:error, message} ->
            reply(id, %{"content" => [%{"type" => "text", "text" => message}], "isError" => true})
        end

      :error ->
        error_reply(id, -32601, "Unknown tool: #{name}")
    end
  end

  defp handle_message(%{"id" => id}, _tools, _name),
    do: error_reply(id, -32601, "Method not found")

  defp handle_message(_other, _tools, _name), do: :ok

  defp reply(id, result), do: send_json(%{"jsonrpc" => "2.0", "id" => id, "result" => result})

  defp error_reply(id, code, message),
    do:
      send_json(%{
        "jsonrpc" => "2.0",
        "id" => id,
        "error" => %{"code" => code, "message" => message}
      })

  # Only ever JSON on stdout - anything you'd print for a human goes to
  # stderr, or you'll corrupt the protocol stream.
  defp send_json(message), do: IO.puts(Jason.encode!(message))
end
