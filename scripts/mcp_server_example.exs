# A tiny MCP server used by Module 6.
#
# MCP (Model Context Protocol) is an open standard for exposing tools to any
# AI client over a simple protocol. Editors, IDEs and agent frameworks can all
# speak it, so a tool you publish once works everywhere.
#
# This server exposes two toy tools over stdio, using
# `ElxAgentTutorial.MCP.Server` (see that module for the ~60-line protocol
# implementation). `06_mcp_tools.exs` launches it as a subprocess and hands
# its tools to an agent. You normally would not run this file directly.

alias ElxAgentTutorial.{MCP, Tool}

nth_prime =
  Tool.from_fun(
    "nth_prime",
    "Return the nth prime number (1-indexed, so nth_prime(n: 1) == 2).",
    %{"n" => %{type: "integer", doc: "Which prime to return, 1-indexed."}},
    fn %{"n" => n} ->
      Stream.iterate(2, &(&1 + 1))
      |> Stream.filter(fn candidate ->
        Enum.all?(2..max(2, trunc(:math.sqrt(candidate))), fn d ->
          candidate == d or rem(candidate, d) != 0
        end)
      end)
      |> Enum.at(trunc(n) - 1)
      |> to_string()
    end
  )

roman_numeral =
  Tool.from_fun(
    "roman_numeral",
    "Convert an integer between 1 and 3999 into a Roman numeral string.",
    %{"number" => %{type: "integer", doc: "An integer between 1 and 3999."}},
    fn %{"number" => number} ->
      number = trunc(number)

      if number < 1 or number > 3999 do
        raise "number must be between 1 and 3999"
      end

      table = [
        {1000, "M"},
        {900, "CM"},
        {500, "D"},
        {400, "CD"},
        {100, "C"},
        {90, "XC"},
        {50, "L"},
        {40, "XL"},
        {10, "X"},
        {9, "IX"},
        {5, "V"},
        {4, "IV"},
        {1, "I"}
      ]

      {result, _remainder} =
        Enum.reduce(table, {"", number}, fn {value, symbol}, {acc, remaining} ->
          count = div(remaining, value)
          {acc <> String.duplicate(symbol, count), rem(remaining, value)}
        end)

      result
    end
  )

MCP.Server.serve([nth_prime, roman_numeral], name: "tutorial-tools")
