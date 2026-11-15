defmodule ElxAgentTutorial.Web.Router do
  @moduledoc """
  Module 7 - give your agent a web UI.

  A small `Plug` app served by `Bandit`, streaming each agent step to the
  browser over Server-Sent Events as it happens - a "watch the reasoning
  happen live" view built from two well-known Elixir libraries.

  `run/2` builds the agent (any struct with a `run/2`: `ToolCallingAgent` or
  `CodeAgent` both work), starts Bandit, and blocks until Ctrl-C. One request
  handler streams: it asks the agent to run in a `Task`, and forwards
  `:telemetry` step events to the connection as they fire.
  """

  use Plug.Router, copy_opts_to_assign: :opts

  plug(:match)
  plug(:dispatch)

  get "/" do
    Plug.Conn.send_resp(conn, 200, index_html())
  end

  get "/ask" do
    conn = Plug.Conn.fetch_query_params(conn)
    question = conn.params["q"] || ""

    agent = conn.assigns.opts[:agent]

    conn =
      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.put_resp_header("cache-control", "no-cache")
      |> Plug.Conn.send_chunked(200)

    ref = make_ref()
    handler_id = {__MODULE__, ref}
    parent = self()

    :telemetry.attach(
      handler_id,
      [:elx_agent_tutorial, :agent, :step],
      fn _event, measurements, metadata, _config ->
        send(parent, {:step, metadata.step, measurements})
      end,
      nil
    )

    task =
      Task.async(fn ->
        try do
          agent.__struct__.run(agent, question)
        rescue
          e ->
            {:error, Exception.format(:error, e, __STACKTRACE__),
             %{usage: %ElxAgentTutorial.Model.Usage{}}}
        end
      end)

    conn = stream_steps(conn, task.ref)
    :telemetry.detach(handler_id)
    conn
  end

  match _ do
    Plug.Conn.send_resp(conn, 404, "not found")
  end

  defp stream_steps(conn, task_ref) do
    receive do
      {:step, step, _measurements} ->
        case Plug.Conn.chunk(conn, sse("step", step_json(step))) do
          {:ok, conn} -> stream_steps(conn, task_ref)
          {:error, _reason} -> conn
        end

      {^task_ref, result} ->
        Process.demonitor(task_ref, [:flush])
        {:ok, conn} = Plug.Conn.chunk(conn, sse("final", result_json(result)))
        conn

      {:DOWN, ^task_ref, :process, _pid, reason} ->
        {:ok, conn} =
          Plug.Conn.chunk(conn, sse("error", Jason.encode!(%{message: inspect(reason)})))

        conn
    after
      120_000 ->
        {:ok, conn} = Plug.Conn.chunk(conn, sse("error", Jason.encode!(%{message: "timed out"})))

        conn
    end
  end

  defp step_json(%ElxAgentTutorial.Step{} = step) do
    Jason.encode!(%{
      step: step.step_number,
      tool_calls:
        Enum.map(
          step.tool_calls || [],
          &%{name: &1.name, input: &1.input, result: preview(&1.result)}
        ),
      code: step.code,
      observation: preview(step.observation),
      error: step.error,
      tokens: ElxAgentTutorial.Model.Usage.total(step.usage),
      duration_ms: step.duration_ms
    })
  end

  defp result_json({:ok, answer, run}),
    do:
      Jason.encode!(%{
        answer: answer,
        html: markdown_to_html(answer),
        usage: usage_json(run.usage)
      })

  defp result_json({:error, reason, run}),
    do: Jason.encode!(%{error: inspect(reason), usage: usage_json(run.usage)})

  # The agent's answer is markdown (it often includes **bold**, lists, and
  # headings) - render it to HTML server-side rather than shipping the raw
  # text and a JS markdown library to the browser. `MDEx` disables raw HTML
  # passthrough by default, so embedded `<script>`-style content from a
  # search result the model quoted can't execute here.
  defp markdown_to_html(markdown) do
    MDEx.to_html!(markdown, extension: [table: true, strikethrough: true, autolink: true])
  end

  defp usage_json(usage) do
    %{
      input_tokens: usage.input_tokens,
      output_tokens: usage.output_tokens,
      cost: Float.round(ElxAgentTutorial.Model.Usage.cost(usage), 4)
    }
  end

  defp preview(nil), do: nil
  defp preview(text) when byte_size(text) > 500, do: String.slice(text, 0, 500) <> "..."
  defp preview(text), do: text

  defp sse(event, data), do: "event: #{event}\ndata: #{data}\n\n"

  @doc """
  Start the web UI for `agent` (built by the caller - see
  `scripts/07_web_app.exs` and `capstone/app.exs`) and block until Ctrl-C.

  `:port` defaults to the `PORT` env var, or 4000 if that isn't set either -
  so the same call works locally and wherever else you might host it.
  """
  def run(agent, opts \\ []) do
    port = Keyword.get(opts, :port) || String.to_integer(System.get_env("PORT") || "4000")
    title = Keyword.get(opts, :title, "Agent")

    plug_opts = [agent: agent, title: title]

    {:ok, _pid} =
      Bandit.start_link(
        plug: {__MODULE__, plug_opts},
        scheme: :http,
        ip: {0, 0, 0, 0},
        port: port
      )

    IO.puts("Starting the web UI at http://127.0.0.1:#{port} - open it in your browser.")
    IO.puts("Press Ctrl-C to stop.\n")

    Process.sleep(:infinity)
  end

  defp index_html do
    """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>Agent</title>
      <style>
        body { font-family: -apple-system, sans-serif; max-width: 720px; margin: 2rem auto; padding: 0 1rem; }
        #status { color: #888; font-size: 0.9rem; margin: 1rem 0; }
        #answer { background: #f6f6f6; padding: 1rem 1.25rem; border-radius: 6px; line-height: 1.5; }
        #answer > :first-child { margin-top: 0; }
        #answer > :last-child { margin-bottom: 0; }
        #answer p, #answer ul, #answer ol { margin: 0 0 0.75rem; }
        #answer ul, #answer ol { padding-left: 1.25rem; }
        #answer h1, #answer h2, #answer h3 { margin: 1rem 0 0.5rem; }
        #answer code { background: #e8e8e8; padding: 0.1rem 0.3rem; border-radius: 3px; font-size: 0.9em; }
        #answer pre { background: #e8e8e8; padding: 0.75rem; border-radius: 6px; overflow-x: auto; }
        #answer pre code { background: none; padding: 0; }
        input { width: 70%; padding: 0.5rem; } button { padding: 0.5rem 1rem; }
      </style>
    </head>
    <body>
      <h1>Research Assistant</h1>
      <form id="f">
        <input id="q" placeholder="Ask a question…" autofocus>
        <button>Ask</button>
      </form>
      <div id="status"></div>
      <div id="answer"></div>
      <script>
        const form = document.getElementById('f');
        const status = document.getElementById('status');
        const answer = document.getElementById('answer');
        form.addEventListener('submit', (e) => {
          e.preventDefault();
          status.textContent = 'Thinking…'; answer.textContent = '';
          const q = document.getElementById('q').value;
          const es = new EventSource('/ask?q=' + encodeURIComponent(q));
          es.addEventListener('final', (e) => {
            const r = JSON.parse(e.data);
            status.textContent = '';
            // r.html is markdown rendered server-side (MDEx); errors are
            // plain Elixir-inspect text, so those stay as textContent.
            if (r.html) {
              answer.innerHTML = r.html;
            } else {
              answer.textContent = r.error;
            }
            es.close();
          });
          es.addEventListener('error', () => es.close());
        });
      </script>
    </body>
    </html>
    """
  end
end
