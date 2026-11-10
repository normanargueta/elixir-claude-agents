defmodule ElxAgentTutorial.Tools.VisitWebpage do
  @moduledoc """
  Fetches a URL and returns its text content, stripped of markup. Used from
  Module 5 onward, and by the capstone, to actually read a page a search
  result pointed at.
  """

  use ElxAgentTutorial.Tool

  @max_chars 8000

  @impl true
  def name, do: "visit_webpage"

  @impl true
  def description, do: "Fetch a webpage by URL and return its text content (HTML tags stripped)."

  @impl true
  def inputs,
    do: %{"url" => %{type: "string", doc: "The full URL to fetch, e.g. https://example.com/page"}}

  @impl true
  def forward(%{"url" => url}) do
    case Req.get(url,
           headers: [{"user-agent", "Mozilla/5.0 (compatible; elx-agent-tutorial/0.1)"}],
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: html}} when is_binary(html) -> to_text(html)
      {:ok, %{status: status}} -> "Fetch failed with HTTP #{status}."
      {:error, reason} -> "Fetch failed: #{inspect(reason)}"
    end
  end

  defp to_text(html) do
    html
    |> String.replace(~r/<(script|style)[^>]*>.*?<\/\1>/is, "")
    |> String.replace(~r/<[^>]+>/, "\n")
    |> String.replace(~r/&nbsp;/, " ")
    |> String.replace(~r/\n{2,}/, "\n")
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
    |> String.slice(0, @max_chars)
  end
end
