defmodule Mix.Tasks.Antisocial.GenInvite do
  use Mix.Task

  @shortdoc "Generate a one-time login link for an existing user"

  @moduledoc """
  Generates a login invite token for an existing user and prints the URL.

  ## Usage

      mix antisocial.gen_invite USERNAME

  ## Examples

      mix antisocial.gen_invite alice
  """

  def run([username]) do
    Mix.Task.run("app.start")

    alias Antisocial.Accounts

    case Accounts.get_user_by_username(username) do
      nil ->
        Mix.shell().error("No user found with username: #{username}")

      user ->
        {:ok, token} = Accounts.create_login_token(user)
        host = System.get_env("PHX_HOST") || "localhost:4481"
        scheme = if System.get_env("PHX_HOST"), do: "https", else: "http"
        Mix.shell().info("""

        Login link for #{username} (valid 15 minutes):
          #{scheme}://#{host}/invite/#{token.token}

        Or use device code: #{token.device_code}
          (Enter username + this code on the login page)
        """)
    end
  end

  def run(_) do
    Mix.shell().error("Usage: mix antisocial.gen_invite USERNAME")
  end
end
