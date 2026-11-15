# Module 7 - Give your agent a web UI
# ===================================
#
# `ElxAgentTutorial.Web.Router` wraps an agent in a small `Plug` app served by
# `Bandit`, streaming every step - the tool calls, the observations - into
# the *browser* over Server-Sent Events as they happen: a lightweight HTTP
# server that streams, which is what the BEAM is good at.
#
# `Web.Router.run/2` is also exactly what you'd deploy: point a release or a
# `mix run --no-halt` at it, same module, same `run/2` call (see
# `capstone/app.exs`).
#
# Run it:
#     mix run scripts/07_web_app.exs
#
# then open http://127.0.0.1:4000 in your browser. Ctrl-C to stop.

alias ElxAgentTutorial.{ToolCallingAgent, Tools, Web}

agent =
  ToolCallingAgent.new(
    tools: [Tools.WebSearch.to_tool(), Tools.VisitWebpage.to_tool()],
    max_steps: 8
  )

Web.Router.run(agent, port: 4000, title: "Agent")
