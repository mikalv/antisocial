defmodule Mix.Tasks.Antisocial.ResetOnboarding do
  use Mix.Task

  @shortdoc "Reset onboarding for a user so they go through the wizard again"

  def run([username]) do
    Mix.Task.run("app.start")

    alias Antisocial.{Accounts, Repo}

    case Accounts.get_user_by_username(username) do
      nil ->
        Mix.shell().error("Bruker ikke funnet: #{username}")

      user ->
        user
        |> Ecto.Changeset.change(onboarded_at: nil)
        |> Repo.update!()

        Mix.shell().info("✓ Onboarding nullstilt for #{username}. Logger inn → /onboarding")
    end
  end

  def run(_) do
    Mix.shell().info("Bruk: mix antisocial.reset_onboarding USERNAME")
  end
end
