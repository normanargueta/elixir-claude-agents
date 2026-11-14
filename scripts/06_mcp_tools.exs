# Module 6 - Don't build every tool: load them
# ============================================
#
# You rarely need to hand-write every tool. `ElxAgentTutorial.MCP.Client`
# connects to any MCP (Model Context Protocol) server and turns its tools into
# `%Tool{}`s for the duration of a function.
#
# `MCP.Client.with_tools/3` spawns the server as a subprocess, does the
# protocol handshake, hands your function the live tools, and closes the
# subprocess when you return - so build and run the agent *inside* the
# function.
#
# There's a real trust decision buried in "load someone else's tool": MCP
# tools run code, wherever the server process runs it. Only point this at
# servers you control or trust (here, our own `mcp_server_example.exs`).
#
# We use CodeAgent here: every tool in this tutorial takes a single map of
# named arguments, so if the model tries to call one positionally in the code
# it writes (`nth_prime.(25)` instead of `nth_prime.(%{n: 25})`), that's a
# genuine runtime error the agent has to notice and fix on its next step -
# an "error, observe, recover" beat, same as any tool-misuse mistake.
#
# Run it:
#     mix run scripts/06_mcp_tools.exs

alias ElxAgentTutorial.{CodeAgent, MCP, Step}

question = "Work out the 25th prime number, then express that value as a Roman numeral."

MCP.Client.with_tools("mix", ["run", "scripts/mcp_server_example.exs"], fn tools ->
  IO.puts("Tools loaded over MCP: #{inspect(Enum.map(tools, & &1.name))}")

  agent = CodeAgent.new(tools: tools, max_steps: 6)

  IO.puts("\nQuestion: #{question}\n")

  case CodeAgent.run(agent, question) do
    {:ok, answer, run} ->
      IO.puts("\n" <> String.duplicate("=", 70))
      Enum.each(run.steps, &IO.puts(Step.describe(&1)))
      IO.puts("\nFINAL ANSWER: #{answer}")
      IO.puts(String.duplicate("=", 70))

    {:error, reason, run} ->
      IO.puts("\nAgent run failed: #{inspect(reason)}")
      IO.puts("Steps so far:")
      Enum.each(run.steps, &IO.puts("  " <> Step.describe(&1)))
  end
end)
