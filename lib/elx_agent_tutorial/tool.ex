defmodule ElxAgentTutorial.Tool do
  @moduledoc """
  A tool is just a function the agent is allowed to call. Every tool needs
   three things:

     * a NAME          - how the model refers to it
     * a DESCRIPTION + typed INPUTS - so the model knows when and how to use it
     * the CODE to run (`forward/1`)

   Two ways to build one:

     * `use ElxAgentTutorial.Tool` in a module that defines `name/0`,
       `description/0`, `inputs/0` and `forward/1` - a tool as a module
       (Module 2's weather tool).
     * `ElxAgentTutorial.Tool.from_fun/4` with a closure - a tool as a
       function, for one that holds state. A closure over a struct
       (embeddings, an open connection, ...) covers a stateful tool cleanly;
       Module 4's knowledge base does this - see `KnowledgeBase.build/1`.

   In both forms, the description and each input's `:doc` are not comments for
   humans - they are the contract the model reads to decide when and how to
   call the tool. Get those wrong and the agent misuses the tool.
  """

  @enforce_keys [:name, :description, :inputs, :forward]
  defstruct [:name, :description, :inputs, :forward]

  @type input_spec :: %{type: String.t(), doc: String.t()}
  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          inputs: %{optional(String.t()) => input_spec()},
          forward: (map() -> String.t())
        }

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback inputs() :: %{optional(String.t()) => input_spec()}
  @callback forward(map()) :: String.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour ElxAgentTutorial.Tool

      @doc "Build the `%Tool{}` struct for this module."
      def to_tool do
        %ElxAgentTutorial.Tool{
          name: name(),
          description: description(),
          inputs: inputs(),
          forward: &forward/1
        }
      end

      defoverridable to_tool: 0
    end
  end

  @doc "Build a tool from a plain function - the `@tool`-decorator equivalent."
  def from_fun(name, description, inputs, fun) when is_function(fun, 1) do
    %__MODULE__{name: name, description: description, inputs: inputs, forward: fun}
  end

  @doc "Run a tool, returning `{:ok, result}` or `{:error, message}` - never raises."
  def call(%__MODULE__{forward: forward}, args) when is_map(args) do
    {:ok, to_string(forward.(args))}
  rescue
    e -> {:error, Exception.format(:error, e, __STACKTRACE__)}
  end

  @doc "The JSON Schema for this tool's arguments (shared by the Anthropic and MCP shapes)."
  def input_schema(%__MODULE__{inputs: inputs}) do
    properties =
      Map.new(inputs, fn {key, spec} ->
        {to_string(key), %{"type" => spec.type, "description" => spec.doc}}
      end)

    %{"type" => "object", "properties" => properties, "required" => Map.keys(properties)}
  end

  @doc "Anthropic Messages API tool definition: name, description, input_schema."
  def to_anthropic_schema(%__MODULE__{} = tool) do
    %{
      "name" => tool.name,
      "description" => tool.description,
      "input_schema" => input_schema(tool)
    }
  end
end
