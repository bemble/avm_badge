defmodule GPIO do
  @moduledoc false

  def open, do: :sim_gpio
  def set_pin_mode(_pin, _mode), do: :ok
  def set_int(:sim_gpio, _pin, _trigger), do: :ok
  def remove_int(:sim_gpio, _pin), do: :ok
  def digital_read(pin), do: :persistent_term.get({__MODULE__, pin}, :low)
end
