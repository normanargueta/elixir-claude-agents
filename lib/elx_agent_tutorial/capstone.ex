defmodule ElxAgentTutorial.Capstone do
  @moduledoc """
  The capstone - a Research Assistant agent that pulls the whole tutorial
  together:

    * `Tools.WebSearch` + `Tools.VisitWebpage`  (Modules 1-2) - the open web
    * `Tools.KnowledgeBase`                     (Module 4)    - semantic
      search over `priv/data/`, three internal docs for a fictional company
    * a `ToolCallingAgent` to orchestrate        (Module 3)
    * `:max_steps` + `:planning_interval`        (Module 8)   - guard rails

  `build_agent/0` returns a ready agent. `capstone/app.exs` wraps it in the
  web UI; `capstone/agent.exs` runs one question from the command line - see
  both for the entry points (this module holds the reusable logic they share).
  """

  alias ElxAgentTutorial.{ToolCallingAgent, Tools}

  @instructions """
  You are a research assistant.
  - For questions about Northwind Analytics or this tutorial's agent framework, search the knowledge_base first.
  - For anything about current events or the outside world, use web_search and visit_webpage.
  - If the knowledge base and the web disagree, say so.
  - Always end with a short answer followed by a "Sources:" list naming the files
    and/or URLs you actually used.
  """

  @doc "Build the capstone agent. Loads and embeds the knowledge base, so this takes a few seconds."
  def build_agent(data_dir \\ Application.app_dir(:elx_agent_tutorial, "priv/data")) do
    {kb_tool, _chunks, _sources_agent} = Tools.KnowledgeBase.build(data_dir)

    ToolCallingAgent.new(
      tools: [kb_tool, Tools.WebSearch.to_tool(), Tools.VisitWebpage.to_tool()],
      instructions: @instructions,
      max_steps: 10,
      # re-plan every 4 steps; helps on longer tasks
      planning_intervals: 4
    )
  end
end
