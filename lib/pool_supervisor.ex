defmodule ExRabbitPool.PoolSupervisor do
  use DynamicSupervisor

  @type config :: [rabbitmq_config: keyword(), connection_pools: list()]

  @spec start_link(config()) :: Supervisor.on_start()
  def start_link(config) do
    IO.inspect config
    DynamicSupervisor.start_link(__MODULE__, config, name: ExRabbitPool.DynamicSupervisor)
  end

  @spec start_link(config(), atom()) :: Supervisor.on_start()
  def start_link(config, name) do
    IO.puts "Starting with name #{name}"
    DynamicSupervisor.start_link(__MODULE__, config, name: name)
  end

  @impl true
  def init(_config) do
    DynamicSupervisor.init(strategy: :one_for_one, name: ExRabbitPool.DynamicSupervisor)
  end

  def add_pool(rabbitmq_config, pool_config) do
    {_, pool_id} = Keyword.fetch!(pool_config, :name)
    # We are using poolboy's pool as a fifo queue so we can distribute the
    # load between workers
    pool_config = Keyword.merge(pool_config, strategy: :fifo)
    spec = :poolboy.child_spec(pool_id, pool_config, rabbitmq_config)
    DynamicSupervisor.start_child(ExRabbitPool.DynamicSupervisor, spec)
  end

  def remove_pool(pool_id) do
    pool_id = if is_binary(pool_id), do: String.to_atom(pool_id), else: pool_id

    child = Enum.find(DynamicSupervisor.which_children(ExRabbitPool.DynamicSupervisor), fn x -> {_, pid, _, _} = x; Keyword.get(Process.info(pid), :registered_name) == pool_id end)
    if child do
      {_, pid, _, _} = child
      DynamicSupervisor.terminate_child(ExRabbitPool.DynamicSupervisor, pid)
      Logger.debug "Found child #{pool_id} to terminate with pid #{pid}"
      :ok
    else
      Logger.error "Failed to associate child #{pool_id} with pid"
      nil
    end
  end
end
