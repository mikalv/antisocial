defmodule Antisocial.PasskeyChallenge do
  @moduledoc """
  ETS-backed ephemeral store for WebAuthn challenges.
  Challenges expire after 5 minutes. A session_id maps to a Wax.Challenge struct.
  """
  use GenServer

  @ttl_seconds 300
  @table :passkey_challenges
  @cleanup_interval_ms 60_000

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def init(_) do
    :ets.new(@table, [:named_table, :public, :set])
    schedule_cleanup()
    {:ok, []}
  end

  def put(session_id, challenge) do
    expires_at = System.system_time(:second) + @ttl_seconds
    :ets.insert(@table, {session_id, challenge, expires_at})
    :ok
  end

  def pop(session_id) do
    now = System.system_time(:second)
    case :ets.lookup(@table, session_id) do
      [{^session_id, challenge, expires_at}] when expires_at > now ->
        :ets.delete(@table, session_id)
        {:ok, challenge}
      _ ->
        {:error, :not_found}
    end
  end

  def handle_info(:cleanup, state) do
    now = System.system_time(:second)
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup, do: Process.send_after(self(), :cleanup, @cleanup_interval_ms)
end
