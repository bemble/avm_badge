defmodule Badge.Sensors do
  @moduledoc """
  Reads the SC7A20 accelerometer and TMP103 temperature sensor over the
  shared I2C bus.

  Every reading is taken on demand, inside the call that asks for it. This
  process runs no timer, so a page that never asks costs nothing and a caller
  never queues behind background sampling.

  Accelerometer samples are smoothed against the previous reading, so the
  averaging follows how often a page actually polls.

  `arm_motion/0` routes the SC7A20's high-pass motion interrupt to INT1
  (GPIO12), latched. The first event disarms it and wakes `Badge.UI`.
  `park_motion/0` hands INT1 over to light sleep as a wakeup source, and
  `disarm_motion/0` restores the plain reading configuration.
  """

  use GenServer

  import Bitwise

  alias Badge.Accel
  alias Badge.Hardware

  @compile {:no_warn_undefined, [GPIO, I2C]}

  @sc7a20_addr Hardware.sc7a20_addr()
  @tmp103_addr Hardware.tmp103_addr()
  @accel_int_pin Hardware.accel_int_pin()

  @sc7a20_ctrl_reg1 0x20
  @sc7a20_ctrl_reg1_25hz_xyz 0x37
  @sc7a20_odr_hz 25
  @sc7a20_ctrl_reg2 0x21
  @sc7a20_ctrl_reg2_hp_ia1 0x01
  @sc7a20_ctrl_reg3 0x22
  @sc7a20_ctrl_reg3_int_off 0x00
  @sc7a20_ctrl_reg3_i1_ia1 0x40
  @sc7a20_ctrl_reg4 0x23
  @sc7a20_ctrl_reg4_bdu_2g 0x80
  @sc7a20_ctrl_reg5 0x24
  @sc7a20_ctrl_reg5_lir_int1 0x08
  @sc7a20_reference 0x26
  @sc7a20_int1_cfg 0x30
  @sc7a20_int1_cfg_or_xyz_high 0x2A
  @sc7a20_int1_src 0x31
  @sc7a20_int1_ths 0x32
  @sc7a20_int1_duration 0x33
  @sc7a20_out_x_l 0x28
  @sc7a20_auto_increment 0x80

  @tmp103_reg 0x00

  # Motion that wakes the screen, after the high-pass filter.
  @motion_mg 320
  @motion_ms 80

  def start_link(_arg) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Reads the accelerometer now, in milli-g in the panel's frame (see `Badge.Accel`)."
  @spec acceleration() :: Accel.mg()
  def acceleration do
    GenServer.call(__MODULE__, :acceleration)
  end

  @doc "Reads the accelerometer now and returns roll and pitch as `Badge.Accel.orientation/1` does."
  @spec orientation() :: {integer, integer}
  def orientation do
    GenServer.call(__MODULE__, :orientation)
  end

  @doc "Reads the TMP103 now in whole degrees C, or :unavailable if the read fails."
  @spec temperature() :: integer | :unavailable
  def temperature do
    GenServer.call(__MODULE__, :temperature)
  end

  @doc "Arms the motion interrupt; the first event disarms it and calls `Badge.UI.wake/0`."
  @spec arm_motion() :: :ok
  def arm_motion, do: GenServer.cast(__MODULE__, :arm_motion)

  @doc "Stops motion from waking anything and restores the plain reading configuration."
  @spec disarm_motion() :: :ok
  def disarm_motion, do: GenServer.cast(__MODULE__, :disarm_motion)

  @doc """
  Readies an armed motion interrupt for light sleep, which then wakes on INT1 high.

  `:parked` leaves the sensor armed with GPIO12's interrupt removed, as the
  wakeup makes the pin level-triggered. `:moved` means motion already fired
  and is disarmed, so the badge should wake instead; `:off` means not armed.
  """
  @spec park_motion() :: :parked | :moved | :off
  def park_motion, do: GenServer.call(__MODULE__, :park_motion)

  @impl true
  def init(:ok) do
    i2c = I2C.open(scl: Hardware.i2c_scl(), sda: Hardware.i2c_sda(), clock_speed_hz: 100_000)

    :ok = I2C.write_bytes(i2c, @sc7a20_addr, @sc7a20_ctrl_reg1, @sc7a20_ctrl_reg1_25hz_xyz)
    :ok = I2C.write_bytes(i2c, @sc7a20_addr, @sc7a20_ctrl_reg4, @sc7a20_ctrl_reg4_bdu_2g)

    # INT1 stays off: readings are polled, so a data-ready line would only generate traffic.
    :ok = I2C.write_bytes(i2c, @sc7a20_addr, @sc7a20_ctrl_reg3, @sc7a20_ctrl_reg3_int_off)

    gpio = GPIO.open()
    _ = GPIO.set_pin_mode(@accel_int_pin, :input)
    # A listener left by an earlier incarnation would outlive it in the driver.
    _ = GPIO.remove_int(gpio, @accel_int_pin)

    :io.format(~c"Sensors: sc7a20 and tmp103, polled on demand~n")

    {:ok, %{i2c: i2c, gpio: gpio, accel: nil, motion: :off}}
  end

  @impl true
  def handle_call(:acceleration, _from, state) do
    accel = read_accel(state)

    {:reply, accel, %{state | accel: accel}}
  end

  def handle_call(:orientation, _from, state) do
    accel = read_accel(state)

    {:reply, Accel.orientation(accel), %{state | accel: accel}}
  end

  def handle_call(:temperature, _from, state) do
    {:reply, read_temp(state.i2c), state}
  end

  def handle_call(:park_motion, _from, %{motion: :armed} = state) do
    _ = GPIO.remove_int(state.gpio, @accel_int_pin)

    case GPIO.digital_read(@accel_int_pin) do
      :high ->
        :io.format(~c"Sensors: motion wake~n")
        {:reply, :moved, disarm(state)}

      _low ->
        {:reply, :parked, %{state | motion: :parked}}
    end
  end

  def handle_call(:park_motion, _from, state), do: {:reply, state.motion, state}

  @impl true
  def handle_cast(:arm_motion, state), do: {:noreply, arm(state)}

  def handle_cast(:disarm_motion, %{motion: :off} = state), do: {:noreply, state}

  def handle_cast(:disarm_motion, %{motion: :parked} = state) do
    case read_int1_src(state.i2c) do
      {:ok, src} ->
        if Accel.moved?(src), do: :io.format(~c"Sensors: motion wake from light sleep~n")

      _error ->
        :ok
    end

    {:noreply, disarm(state)}
  end

  def handle_cast(:disarm_motion, state), do: {:noreply, disarm(state)}

  def handle_cast(request, state), do: {:stop, {:bad_cast, request}, state}

  # INT1_SRC tells a real event from a glitch, and reading it clears the latch.
  @impl true
  def handle_info({:gpio_interrupt, @accel_int_pin}, %{motion: :armed} = state) do
    case read_int1_src(state.i2c) do
      {:ok, src} ->
        case Accel.moved?(src) do
          true ->
            :io.format(~c"Sensors: motion wake~n")
            Badge.UI.wake()
            {:noreply, disarm(state)}

          false ->
            {:noreply, state}
        end

      _error ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp arm(state) do
    i2c = state.i2c

    write(i2c, @sc7a20_ctrl_reg3, @sc7a20_ctrl_reg3_int_off)
    write(i2c, @sc7a20_ctrl_reg2, @sc7a20_ctrl_reg2_hp_ia1)
    write(i2c, @sc7a20_int1_ths, Accel.threshold(@motion_mg))
    write(i2c, @sc7a20_int1_duration, Accel.duration(@motion_ms, @sc7a20_odr_hz))
    write(i2c, @sc7a20_ctrl_reg5, @sc7a20_ctrl_reg5_lir_int1)
    write(i2c, @sc7a20_int1_cfg, @sc7a20_int1_cfg_or_xyz_high)
    # Reading REFERENCE resets the high-pass filter to the badge's current pose.
    _ = I2C.read_bytes(i2c, @sc7a20_addr, @sc7a20_reference, 1)
    write(i2c, @sc7a20_ctrl_reg3, @sc7a20_ctrl_reg3_i1_ia1)

    # Removed first, since a second set_int on the same pin is refused.
    _ = GPIO.remove_int(state.gpio, @accel_int_pin)
    _ = GPIO.set_int(state.gpio, @accel_int_pin, :rising)

    # Cleared after the edge is armed: INT1 already high would never rise again.
    _ = read_int1_src(i2c)

    %{state | motion: :armed}
  end

  defp disarm(state) do
    i2c = state.i2c

    _ = GPIO.remove_int(state.gpio, @accel_int_pin)
    write(i2c, @sc7a20_ctrl_reg3, @sc7a20_ctrl_reg3_int_off)
    write(i2c, @sc7a20_int1_cfg, 0x00)
    write(i2c, @sc7a20_ctrl_reg5, 0x00)
    write(i2c, @sc7a20_ctrl_reg2, 0x00)
    _ = read_int1_src(i2c)

    %{state | motion: :off}
  end

  defp write(i2c, register, value), do: I2C.write_bytes(i2c, @sc7a20_addr, register, value)

  defp read_int1_src(i2c) do
    case I2C.read_bytes(i2c, @sc7a20_addr, @sc7a20_int1_src, 1) do
      {:ok, <<src>>} -> {:ok, src}
      other -> other
    end
  end

  defp read_accel(%{i2c: i2c, accel: previous}) do
    case I2C.read_bytes(i2c, @sc7a20_addr, @sc7a20_out_x_l ||| @sc7a20_auto_increment, 6) do
      {:ok, bytes} -> Accel.average(previous, Accel.decode(bytes))
      {:error, _reason} -> previous || {0, 0, 0}
    end
  end

  defp read_temp(i2c) do
    case I2C.read_bytes(i2c, @tmp103_addr, @tmp103_reg, 1) do
      {:ok, <<raw>>} -> signed_byte(raw)
      {:error, _reason} -> :unavailable
    end
  end

  # TMP103 register 0x00 is a signed 8-bit whole-degree-C reading.
  defp signed_byte(raw) when raw >= 128, do: raw - 256
  defp signed_byte(raw), do: raw
end
