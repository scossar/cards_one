defmodule CardsOne.SemanticSearch.Worker do
  @moduledoc false
  use GenServer
  require Logger

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def status, do: GenServer.call(__MODULE__, :status)

  def wake do
    if pid = Process.whereis(__MODULE__), do: send(pid, :index)
    :ok
  end

  @impl true
  def init(_opts) do
    status =
      cond do
        not Application.get_env(:cards_one, :semantic_search_enabled, true) -> :disabled
        Process.whereis(CardsOne.SemanticSearch.Serving) -> :ready
        true -> :loading
      end

    if status == :loading, do: send(self(), :load)
    if status == :ready, do: send(self(), :index)
    {:ok, %{status: status, task: nil, timer: nil}}
  end

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state.status, state}

  @impl true
  def handle_info(:load, %{task: nil} = state) do
    task =
      Task.Supervisor.async_nolink(CardsOne.SemanticSearch.Tasks, fn ->
        CardsOne.SemanticSearch.Model.load()
      end)

    {:noreply, %{state | task: {:load, task.ref}, status: :loading}}
  end

  def handle_info(:index, %{status: :ready, task: nil} = state) do
    if state.timer, do: Process.cancel_timer(state.timer)

    task =
      Task.Supervisor.async_nolink(
        CardsOne.SemanticSearch.Tasks,
        &CardsOne.SemanticSearch.index_pending/0
      )

    {:noreply, %{state | task: {:index, task.ref}, timer: nil}}
  end

  def handle_info({ref, {:ok, serving}}, %{task: {:load, ref}} = state) do
    Process.demonitor(ref, [:flush])

    case DynamicSupervisor.start_child(
           CardsOne.SemanticSearch.Servings,
           {Nx.Serving, serving: serving, name: CardsOne.SemanticSearch.Serving}
         ) do
      {:ok, _pid} ->
        send(self(), :index)
        {:noreply, %{state | task: nil, status: :ready}}

      {:error, reason} ->
        failed(state, reason)
    end
  end

  def handle_info({ref, result}, %{task: {:index, ref}} = state) do
    Process.demonitor(ref, [:flush])

    delay =
      case result do
        {:ok, count} when count > 0 ->
          0

        {:ok, 0} ->
          5_000

        {:error, reason} ->
          Logger.warning("Semantic indexing deferred: #{inspect(reason)}")
          5_000
      end

    {:noreply, %{state | task: nil, timer: Process.send_after(self(), :index, delay)}}
  end

  def handle_info({ref, {:error, reason}}, %{task: {:load, ref}} = state) do
    Process.demonitor(ref, [:flush])
    failed(state, reason)
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task: {kind, ref}} = state) do
    if kind == :load do
      failed(state, reason)
    else
      {:noreply, %{state | task: nil, timer: Process.send_after(self(), :index, 5_000)}}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp failed(state, reason) do
    Logger.warning("Semantic model unavailable: #{inspect(reason)}")
    Process.send_after(self(), :load, 60_000)
    {:noreply, %{state | task: nil, status: :unavailable}}
  end
end
