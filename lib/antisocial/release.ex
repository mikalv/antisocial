defmodule Antisocial.Release do
  @app :antisocial

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def create_user(username, password, display_name \\ nil) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Antisocial.Repo, fn _repo ->
        case Antisocial.Accounts.create_user(%{
               username: username,
               password: password,
               display_name: display_name
             }) do
          {:ok, user} ->
            {:ok, token} = Antisocial.Accounts.create_invite_token(user)
            IO.puts("✓ User '#{username}' created.")
            IO.puts("  Invite URL: /invite/#{token.token}")
            {:ok, user}

          {:error, changeset} ->
            IO.puts("✗ Failed: #{inspect(changeset.errors)}")
            {:error, changeset}
        end
      end)
  end

  def seed_channels do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Antisocial.Repo, fn _repo ->
        Antisocial.Repo.insert!(
          %Antisocial.Chat.Channel{slug: "generelt", name: "Generelt", pin_required: false},
          on_conflict: :nothing
        )

        IO.puts("✓ #generelt channel ready.")
        {:ok, :seeded}
      end)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
