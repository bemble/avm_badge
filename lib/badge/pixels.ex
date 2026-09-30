defmodule Badge.Pixels do
  @moduledoc """
  The LED ring in the badge's corners.

  Effects run in the `leds` port driver, in C, so this process only hands
  the driver a setting (see `Badge.LedEffect`) when it changes and remembers
  it in NVS. `start_link/1` takes the module that talks to the chain:
  `Badge.Pixels.Port` on the badge, a stand-in in the simulator.
  """

  use GenServer

  alias Badge.Hardware
  alias Badge.LedEffect
  alias Badge.Nvs

  @nvs_key :led_mode

  # A setting stepped through on the page is saved once it stops changing.
  @save_ms 1500

  def start_link(driver) do
    GenServer.start_link(__MODULE__, driver, name: __MODULE__)
  end

  @doc "Shows a setting now, and saves it once it has stopped changing."
  @spec set(map) :: :ok
  def set(setting), do: GenServer.cast(__MODULE__, {:set, setting})

  @doc "What the ring is set to, so a page can adopt it rather than reset it."
  @spec setting() :: map
  def setting, do: GenServer.call(__MODULE__, :setting)

  @doc "Darkens the ring, leaving the setting to come back to."
  @spec sleep() :: :ok
  def sleep, do: GenServer.cast(__MODULE__, :sleep)

  @doc "Puts back whatever was showing before sleep."
  @spec wake() :: :ok
  def wake, do: GenServer.cast(__MODULE__, :wake)

  @doc "Flashes the whole ring in a hue for `ms` over whatever is running, which then resumes."
  @spec flash(non_neg_integer, pos_integer) :: :ok
  def flash(hue, ms \\ LedEffect.flash_ms()), do: GenServer.cast(__MODULE__, {:flash, hue, ms})

  @impl true
  def init(driver) do
    chain = driver.open(Hardware.pixel_data(), Hardware.pixel_count())
    :ok = driver.call(chain, {:order, Hardware.pixel_order()})

    state = %{driver: driver, chain: chain, setting: LedEffect.default(), asleep: false, due: nil}

    {:ok, state, {:continue, :restore}}
  end

  # Reads NVS after init/1 returns, not during it.
  @impl true
  def handle_continue(:restore, state) do
    setting = LedEffect.decode(Nvs.get(@nvs_key))
    :io.format(~c"Pixels: ~s~n", [LedEffect.encode(setting)])

    {:noreply, show(%{state | setting: setting})}
  end

  @impl true
  def handle_call(:setting, _from, state), do: {:reply, state.setting, state}

  @impl true
  def handle_cast({:set, setting}, %{setting: setting} = state), do: {:noreply, state}

  def handle_cast({:set, setting}, state) do
    due = make_ref()
    Process.send_after(self(), {:save, due}, @save_ms)

    {:noreply, show(%{state | setting: setting, due: due})}
  end

  def handle_cast(:sleep, state), do: {:noreply, show(%{state | asleep: true})}
  def handle_cast(:wake, state), do: {:noreply, show(%{state | asleep: false})}

  # A badge in a pocket stays dark, flash or not.
  def handle_cast({:flash, _hue, _ms}, %{asleep: true} = state), do: {:noreply, state}

  def handle_cast({:flash, hue, ms}, state) do
    state.driver.call(state.chain, LedEffect.flash(hue, ms))

    {:noreply, state}
  end

  @impl true
  def handle_info({:save, due}, %{due: due} = state) do
    Nvs.put(@nvs_key, LedEffect.encode(state.setting))

    {:noreply, %{state | due: nil}}
  end

  # A newer change has its own save coming.
  def handle_info({:save, _stale}, state), do: {:noreply, state}

  defp show(%{asleep: true} = state) do
    state.driver.call(state.chain, LedEffect.command(%{effect: :off}))
    state
  end

  defp show(state) do
    state.driver.call(state.chain, LedEffect.command(state.setting))
    state
  end
end
