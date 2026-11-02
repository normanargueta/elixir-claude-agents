defmodule ElxAgentTutorial.Tools.Weather do
  @moduledoc """
  Module 2's hand-written tool: current weather for a set of coordinates, via
  the free Open-Meteo API (no API key required). The description and each
  input's `doc:` are not comments, they are what the model reads to decide
  when and how to call this tool.
  """

  use ElxAgentTutorial.Tool

  @impl true
  def name, do: "get_current_weather"

  @impl true
  def description, do: "Get the current weather at a set of coordinates (no API key required)."

  @impl true
  def inputs do
    %{
      "latitude" => %{type: "number", doc: "Latitude in decimal degrees, e.g. 48.85 for Paris."},
      "longitude" => %{type: "number", doc: "Longitude in decimal degrees, e.g. 2.35 for Paris."}
    }
  end

  @impl true
  def forward(%{"latitude" => lat, "longitude" => lon}) do
    case Req.get("https://api.open-meteo.com/v1/forecast",
           params: [latitude: lat, longitude: lon, current_weather: true],
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: %{"current_weather" => w}}} ->
        "temperature=#{w["temperature"]}C, windspeed=#{w["windspeed"]}km/h, weathercode=#{w["weathercode"]}"

      {:ok, %{status: status}} ->
        "Weather lookup failed with HTTP #{status}."

      {:error, reason} ->
        "Weather lookup failed: #{inspect(reason)}"
    end
  end
end
