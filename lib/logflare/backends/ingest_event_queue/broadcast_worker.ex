defmodule Logflare.Backends.IngestEventQueue.BroadcastWorker do
  @moduledoc """
  A worker that broadcasts all source-backend buffer statistics periodically for the entire node.

  Broadcasts cluster buffer length of a given queue (an integer) locally.
  Broadcasts local buffer length of a given queue globally
  """
  use GenServer
  alias Logflare.Source
  alias Logflare.Backends.IngestEventQueue
  alias Logflare.PubSubRates
  require Logger
  @ets_table_mapper :ingest_event_queue_mapping

  @default_interval 2_500

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    state = %{interval: Keyword.get(opts, :interval, @default_interval)}
    Process.send_after(self(), :global_broadcast, state.interval * 2)
    Process.send_after(self(), :local_broadcast, state.interval)
    {:ok, state}
  end

  def handle_info(:global_broadcast, state) do
    :ets.foldl(
      fn {sid_bid, _tid}, _ ->
        global_broadcast_producer_buffer_len(sid_bid)
        nil
      end,
      nil,
      @ets_table_mapper
    )

    Process.send_after(self(), :global_broadcast, state.interval * 2)
    {:noreply, state}
  end

  def handle_info(:local_broadcast, state) do
    :ets.foldl(
      fn {sid_bid, _tid}, _ ->
        local_broadcast_cluster_length(sid_bid)
        nil
      end,
      nil,
      @ets_table_mapper
    )

    Process.send_after(self(), :local_broadcast, state.interval)
    {:noreply, state}
  end

  defp global_broadcast_producer_buffer_len({source_id, backend_id} = sid_bid) do
    len =
      case IngestEventQueue.count_pending(sid_bid) do
        v when is_integer(v) -> v
        _ -> 0
      end

    local_buffer = %{Node.self() => %{len: len}}
    PubSubRates.global_broadcast_rate({:buffers, source_id, backend_id, local_buffer})
  end

  defp local_broadcast_cluster_length({source_id, backend_id}) do
    payload = %{
      buffer: PubSubRates.Cache.get_cluster_buffers(source_id),
      source_id: source_id,
      backend_id: backend_id
    }

    Source.ChannelTopics.local_broadcast_buffer(payload)
  end
end
