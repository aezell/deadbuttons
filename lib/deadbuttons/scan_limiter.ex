defmodule Deadbuttons.ScanLimiter do
  @moduledoc """
  Limits the number of concurrent scans to avoid OOM on small machines.
  """

  use Agent

  @max_concurrent 3

  def start_link(_opts) do
    Agent.start_link(fn -> 0 end, name: __MODULE__)
  end

  @doc """
  Try to acquire a scan slot. Returns :ok or :busy.
  """
  def acquire do
    Agent.get_and_update(__MODULE__, fn count ->
      if count < @max_concurrent do
        {:ok, count + 1}
      else
        {:busy, count}
      end
    end)
  end

  @doc """
  Release a scan slot when done.
  """
  def release do
    Agent.update(__MODULE__, fn count -> max(count - 1, 0) end)
  end
end
