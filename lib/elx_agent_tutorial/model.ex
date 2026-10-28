defmodule ElxAgentTutorial.Model do
  @moduledoc """
  The one place the LLM lives.

  Every module in this tutorial calls `chat/2` to talk to Claude. It calls the
  [Anthropic Messages API](https://docs.claude.com/en/api/messages) directly
  with `Req` - one HTTP client, one function, nothing in between.

  Keeping the model id and the request shape in ONE module means that when
  Anthropic ships a newer Sonnet, this is the module you edit.
  """

  @model_id "claude-sonnet-5"
  @api_url "https://api.anthropic.com/v1/messages"
  @anthropic_version "2023-06-01"

  defmodule Usage do
    @moduledoc "Token totals for one request, or accumulated across a run."
    defstruct input_tokens: 0, output_tokens: 0

    # Claude Sonnet list price, USD per token (see the README) - used by
    # Module 8's cost report.
    @input_price 2.00 / 1_000_000
    @output_price 10.00 / 1_000_000

    def total(%__MODULE__{input_tokens: i, output_tokens: o}), do: i + o

    def add(%__MODULE__{} = a, %__MODULE__{} = b) do
      %__MODULE__{
        input_tokens: a.input_tokens + b.input_tokens,
        output_tokens: a.output_tokens + b.output_tokens
      }
    end

    def cost(%__MODULE__{input_tokens: i, output_tokens: o}) do
      i * @input_price + o * @output_price
    end
  end

  @type response :: %{
          content: [map()],
          text: String.t() | nil,
          tool_calls: [map()],
          stop_reason: String.t(),
          usage: Usage.t()
        }

  @doc "The model id every agent in this tutorial is built with."
  def model_id, do: @model_id

  @doc """
  Send one turn to Claude and return the parsed response.

    * `messages` - a list of `%{"role" => ..., "content" => ...}` maps, Anthropic
      Messages API shape.
    * `:system` - the system prompt (string), optional.
    * `:tools` - a list of tool definitions in Anthropic's `input_schema` shape,
      optional.
    * `:max_tokens` - defaults to 4096.

  Never raises: returns `{:error, reason}` uniformly for a non-2xx API
  response, a transport error `Req` itself reports, *and* anything the
  request raises (a Finch/connection-pool error under load, for instance) -
  every caller in this tutorial already knows how to handle `{:error,
  reason}`, so this is the one place that turns "the HTTP stack blew up"
  into that same shape instead of crashing the whole run.
  """
  def chat(messages, opts \\ []) do
    api_key = api_key!()

    body =
      %{
        model: @model_id,
        max_tokens: Keyword.get(opts, :max_tokens, 4096),
        messages: messages,
        # Adaptive thinking is Sonnet 5's only "on" mode; we disable it so a
        # tutorial agent's tool-use loop stays simple to reason about and
        # replay (no thinking blocks to echo back). See the README.
        thinking: %{type: "disabled"}
      }
      |> maybe_put(:system, Keyword.get(opts, :system))
      |> maybe_put(:tools, Keyword.get(opts, :tools))

    case Req.post(@api_url,
           json: body,
           headers: [
             {"x-api-key", api_key},
             {"anthropic-version", @anthropic_version}
           ],
           receive_timeout: 120_000
         ) do
      {:ok, %{status: 200, body: resp}} -> {:ok, parse(resp)}
      {:ok, %{status: status, body: resp}} -> {:error, {status, resp}}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, {:request_failed, Exception.message(e)}}
  end

  defp api_key! do
    case System.get_env("ANTHROPIC_API_KEY") do
      nil ->
        raise """

        ANTHROPIC_API_KEY is not set.
          1. cp .env.example .env
          2. paste your key into .env
        """

      key ->
        key
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp parse(%{"content" => content} = resp) do
    text =
      content
      |> Enum.filter(&(&1["type"] == "text"))
      |> Enum.map_join("", & &1["text"])
      |> case do
        "" -> nil
        t -> t
      end

    tool_calls = Enum.filter(content, &(&1["type"] == "tool_use"))

    usage = resp["usage"] || %{}

    %{
      content: content,
      text: text,
      tool_calls: tool_calls,
      stop_reason: resp["stop_reason"],
      usage: %Usage{
        input_tokens: usage["input_tokens"] || 0,
        output_tokens: usage["output_tokens"] || 0
      }
    }
  end
end
