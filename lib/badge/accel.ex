defmodule Badge.Accel do
  @moduledoc """
  Pure maths for the SC7A20 accelerometer: decoding raw registers,
  exponential averaging, and deriving tilt orientation. No I2C, no process
  state.

  The SC7A20 in normal mode is 10-bit, left-justified in a signed 16-bit
  little-endian pair, +-2g full scale, so 1g = 16384 counts and
  `mg = raw * 1000 / 16384`, simplified here to `raw * 125 / 2048`.

  Samples are in the panel's frame, not the sensor's: x toward the panel's
  right edge, y toward its top edge, z out of the screen. A badge lying face
  up reads `{0, 0, 1000}` and one hanging upright reads `{0, 1000, 0}`.
  """

  import Bitwise

  @type mg :: {integer, integer, integer}

  # INT1_SRC's IA bit: an interrupt event has been latched.
  @int_active 0x40

  @doc """
  Decodes the 6 bytes read from OUT_X_L..OUT_Z_H (0x28..0x2D) into milli-g,
  in the panel's frame.
  """
  @spec decode(binary) :: mg
  def decode(<<x::little-signed-16, y::little-signed-16, z::little-signed-16>>) do
    # The sensor faces the back of the board, so its x and z oppose the panel's.
    {-to_mg(x), to_mg(y), -to_mg(z)}
  end

  defp to_mg(raw), do: div(raw * 125, 2048)

  @doc """
  Exponential moving average, alpha = 1/4, applied per axis. `nil` as the
  previous value adopts `sample` as-is.
  """
  @spec average(mg | nil, mg) :: mg
  def average(nil, sample), do: sample

  def average({px, py, pz}, {x, y, z}) do
    {ema(px, x), ema(py, y), ema(pz, z)}
  end

  defp ema(previous, new), do: previous + div(new - previous, 4)

  @doc """
  Roll and pitch in whole degrees from a milli-g sample.

  Both are zero with the badge face up and level. Roll is positive with the
  right edge lowered, pitch positive with the top edge raised, so a badge
  hanging upright reads a pitch of 90.
  """
  @spec orientation(mg) :: {integer, integer}
  def orientation({x, y, z}) do
    roll = round(:math.atan2(-x, :math.sqrt(y * y + z * z)) * 180 / :math.pi())
    pitch = round(:math.atan2(y, z) * 180 / :math.pi())
    {roll, pitch}
  end

  @doc """
  INT1_THS for a motion threshold in milli-g at +-2g full scale, 16 mg per
  count, clamped to the register's 7 bits and never zero.
  """
  @spec threshold(pos_integer) :: 1..127
  def threshold(mg), do: min(max(div(mg + 8, 16), 1), 127)

  @doc "INT1_DURATION for a motion that must last `ms`, in samples at `odr_hz`, within 7 bits."
  @spec duration(non_neg_integer, pos_integer) :: 0..127
  def duration(ms, odr_hz), do: min(div(ms * odr_hz + 500, 1000), 127)

  @doc "Whether an INT1_SRC reading reports a latched motion event."
  @spec moved?(byte) :: boolean
  def moved?(int1_src), do: (int1_src &&& @int_active) != 0
end
