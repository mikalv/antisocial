defmodule Antisocial.TTLWorker do
  use GenServer

  alias Antisocial.Chat

  @interval_ms 30_000

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    schedule()
    {:ok, []}
  end

  @impl true
  def handle_info(:check_ttl, state) do
    Chat.list_expired_ttl_messages()
    |> Enum.each(fn message ->
      if message.ttl_channel_slug && message.ttl_channel_slug != "" do
        case Chat.get_or_create_channel(message.ttl_channel_slug) do
          {:ok, target} -> Chat.move_message(message, target.id, message.user_id)
          _ -> Chat.archive_message(message)
        end
      else
        Chat.archive_message(message)
      end
    end)

    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :check_ttl, @interval_ms)
end
