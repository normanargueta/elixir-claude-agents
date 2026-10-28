defmodule ElxAgentTutorial.MixProject do
  use Mix.Project

  def project do
    [
      app: :elx_agent_tutorial,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ElxAgentTutorial.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:req, "~> 0.7.5"},
      {:jason, "~> 1.4"},
      {:dotenvy, "~> 1.2"}
    ]
  end
end
