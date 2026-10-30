defmodule ElxAgentTutorial.Tools.WebSearch do
  @moduledoc """
  The web-search tool: searches the web and returns a short, cited summary of
  what it finds. Used from Module 1 onward.

  Scraping a search engine's HTML directly turned out to be unreliable from
  a hosted environment: DuckDuckGo's HTML endpoint returned an outright
  bot-detection page (HTTP 202, no results) on every request, and switching
  to Bing was worse - it returned HTTP 200 but silently served unrelated
  decoy content for some queries (Home Depot's homepage for a search about
  Arctic coordinates) instead of failing loudly, which is far more dangerous
  for an agent than an honest error. Rather than fight search-engine bot
  detection with ever-more-convincing headers, this reuses
  `ElxAgentTutorial.Model` to make a **second, nested** call to Claude with
  Anthropic's own server-side web search tool (`web_search_20260209`)
  enabled - the search itself runs on Anthropic's infrastructure as part of
  that one API call, so there's no HTML to scrape or bot-detection to evade,
  and what comes back is already a cited summary instead of raw markup to
  parse. It costs a small amount of extra Sonnet usage per call (see the
  README's cost note) - worth it for not silently reasoning from wrong data.
  """

  use ElxAgentTutorial.Tool

  alias ElxAgentTutorial.Model

  @impl true
  def name, do: "web_search"

  @impl true
  def description,
    do: "Search the web for a query and return a short, cited summary of what you find."

  @impl true
  def inputs,
    do: %{"query" => %{type: "string", doc: "The search query."}}

  @impl true
  def forward(%{"query" => query}) do
    messages = [
      %{
        "role" => "user",
        "content" =>
          "Search the web for: #{query}\n\n" <>
            "Give a concise summary of what you find (a sentence or a short list), " <>
            "citing the source URL for each fact."
      }
    ]

    case Model.chat(messages,
           tools: [%{"type" => "web_search_20260209", "name" => "web_search", "max_uses" => 3}],
           max_tokens: 1024
         ) do
      {:ok, %{text: text}} when is_binary(text) -> text
      {:ok, _no_text} -> "No results found."
      {:error, reason} -> "Search failed: #{inspect(reason)}"
    end
  end
end
