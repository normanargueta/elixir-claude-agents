import Config

# Module 4 / capstone: Nx needs a compute backend for the embedding model.
# EXLA compiles to XLA and is dramatically faster than the pure-Elixir default;
# it downloads a native binary the first time it builds.
config :nx, default_backend: EXLA.Backend

config :logger, level: :warning
