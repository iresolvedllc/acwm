defmodule Pkg.Repo do
  use Ecto.Repo,
    otp_app: :pkg,
    adapter: Ecto.Adapters.Postgres
end
