defmodule Mix.Tasks.Antisocial.CreateUser do
  use Mix.Task

  @shortdoc "Create a user and optionally generate an invite link"

  @moduledoc """
  Creates a new user account.

      mix antisocial.create_user USERNAME PASSWORD

  Prints the invite link (valid 7 days) that can be sent via SMS.
  The user must change their password on first login.
  """

  def run([username, password]) do
    Mix.Task.run("app.start")

    alias Antisocial.Accounts

    case Accounts.create_user(%{username: username, password: password}) do
      {:ok, user} ->
        {:ok, token} = Accounts.create_invite_token(user)
        host = Application.get_env(:antisocial, AntisocialWeb.Endpoint)[:url][:host] || "localhost:4481"
        scheme = if Mix.env() == :prod, do: "https", else: "http"

        Mix.shell().info("""
        ✓ Bruker opprettet: #{username}

        Invitasjonslenke (gyldig 7 dager):
        #{scheme}://#{host}/invite/#{token.token}

        Del denne via SMS. Brukeren velger nytt passord ved første innlogging.
        """)

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Enum.reduce(opts, msg, fn {key, value}, acc ->
              String.replace(acc, "%{#{key}}", to_string(value))
            end)
          end)

        Mix.shell().error("Feil: #{inspect(errors)}")
    end
  end

  def run(_) do
    Mix.shell().info("Bruk: mix antisocial.create_user USERNAME PASSWORD")
  end
end
