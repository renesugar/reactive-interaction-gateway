defmodule Gateway.Blacklist.PresenceHandler do
  require Logger
  @behaviour Phoenix.Tracker

  alias Gateway.Blacklist

  @blacklist_topic "blacklist"

  def start_link(opts) do
    opts = Keyword.merge([name: __MODULE__], opts)
    GenServer.start_link(
      Phoenix.Tracker,
      [__MODULE__, opts, opts],
      name: __MODULE__)
  end

  # callbacks

  def init(opts) do
    {:ok, blacklist} = Gateway.Blacklist.start_link()
    pubsub = Keyword.fetch!(opts, :pubsub_server)
    {:ok, %{
      pubsub_server: pubsub,
      node_name: Phoenix.PubSub.node_name(pubsub),
      blacklist: blacklist,
      }
    }
  end

  @doc """
  Forwards joins on the "blacklist" topic to the Blacklist server.

  Leave events are ignored, as the Blacklist server doesn't handle them. This is
  because we cannot distinguish between an expiry event and an offline node;
  therefore, each node expires the entries by itself.
  """
  def handle_diff(diff, state) do
    for {topic, {joins, leaves}} <- diff do
      for {key, meta} <- joins do
        if topic == @blacklist_topic do
          [jti, expiry] = [key, Map.get(meta, :expiry)]
          state.blacklist |> Blacklist.add_jti(jti, expiry)
        end
        msg = {:join, key, meta}
        Phoenix.PubSub.direct_broadcast!(state.node_name, state.pubsub_server, topic, msg)
      end
      for {key, meta} <- leaves do
        msg = {:leave, key, meta}
        Phoenix.PubSub.direct_broadcast!(state.node_name, state.pubsub_server, topic, msg)
      end
    end
    {:ok, state}
  end
end
