import Config
import Dotenvy

# Load ANTHROPIC_API_KEY (and anything else) from a local .env file, if
# present. Real environment variables always win over .env.
env = source!([Path.absname(".env"), System.get_env()])

for {key, value} <- env, is_binary(value) do
  System.put_env(key, value)
end

:ok
