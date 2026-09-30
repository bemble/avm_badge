defmodule Badge.LedEffect do
  @moduledoc """
  What the LED ring shows: an effect, a palette and the options that shape it.

  A setting is a plain map:

      %{effect: :chase, palette: :neon, hue: 300, speed: 5, brightness: 40,
        spread: 100, direction: :cw, trail: 50, density: 30}

  `speed` is a step from 1 (slowest) to 10, `hue` is used only by the `:hue`
  palette, and the rest are percentages. The four LEDs sit in the badge's
  corners and form a ring, so `:cw` and `:ccw` are the way motion goes round
  it. `command/1` turns a setting into the request the `leds` port driver
  takes; the animation itself runs in C.

  Stored in NVS as readable text, `chase pal=neon hue=300 spd=5 ...`, and read
  back field by field, so a missing or corrupt field falls back to its
  default without losing the rest. Modes saved by older firmware (`rainbow`,
  `dusk`, `solid:120`, `white`, `off`) still read back as their nearest
  effect.
  """

  alias Badge.Color

  # Each effect with the options it pays attention to, in the order the page lists them.
  @effects [
    {:rainbow, [:speed, :brightness, :spread, :direction]},
    {:drift, [:palette, :speed, :brightness, :spread, :direction]},
    {:breathe, [:palette, :speed, :brightness, :spread]},
    {:chase, [:palette, :speed, :brightness, :trail, :direction]},
    {:bounce, [:palette, :speed, :brightness, :trail]},
    {:twinkle, [:palette, :speed, :brightness, :trail, :density]},
    {:heartbeat, [:palette, :speed, :brightness, :spread]},
    {:candle, [:palette, :speed, :brightness, :density]},
    {:aurora, [:palette, :speed, :brightness, :spread]},
    {:strobe, [:palette, :speed, :brightness]},
    {:glitch, [:palette, :brightness, :density]},
    {:solid, [:palette, :brightness, :spread]},
    {:off, []}
  ]

  @palettes [
    {:neon, [0xFF2BD6, 0x2BD9FF]},
    {:dusk, [0xE85FAF, 0x8A63E8, 0x5CC8F5]},
    {:fire, [0xFFB040, 0xFF6A00, 0xFF2000]},
    {:ocean, [0x0040FF, 0x00C8FF, 0x00FFB0]},
    {:forest, [0x00FF40, 0x80FF00, 0x00A060]},
    {:candy, [0xFF4FA0, 0xFFD0E8, 0x80E0FF]},
    {:ice, [0xFFFFFF, 0x80D0FF]},
    {:white, [0xFFFFFF]},
    {:hue, []}
  ]

  # Milliseconds per cycle, slowest first.
  @periods {30_000, 20_000, 12_000, 8000, 5000, 3000, 2000, 1200, 700, 400}

  @default %{
    effect: :rainbow,
    palette: :neon,
    hue: 300,
    speed: 3,
    brightness: 40,
    spread: 100,
    direction: :cw,
    trail: 50,
    density: 30
  }

  @flash_ms 600

  @doc "How long a flash lasts unless told otherwise."
  @spec flash_ms() :: pos_integer
  def flash_ms, do: @flash_ms

  @doc "The setting used when nothing valid is stored."
  @spec default() :: map
  def default, do: @default

  @doc "Every effect, in the order the page steps through them."
  @spec effects() :: [atom]
  def effects, do: for({effect, _options} <- @effects, do: effect)

  @doc "Every palette, in the order the page steps through them."
  @spec palettes() :: [atom]
  def palettes, do: for({palette, _colours} <- @palettes, do: palette)

  @doc "The options an effect uses, in the order the page lists them."
  @spec options(atom) :: [atom]
  def options(effect), do: find(@effects, effect, [])

  @doc "The palette's colours as `0xRRGGBB` integers; `:hue` is the one colour `hue` names."
  @spec colours(atom, non_neg_integer) :: [non_neg_integer]
  def colours(:hue, hue), do: [Color.rgb888(Color.hsv_to_rgb(hue, 255, 255))]
  def colours(palette, _hue), do: find(@palettes, palette, [0xFFFFFF])

  @doc "The colours a setting shows, for a swatch."
  @spec colours(map) :: [non_neg_integer]
  def colours(%{effect: :rainbow}), do: [0xFF0000, 0xFFFF00, 0x00FF00, 0x00FFFF, 0x0000FF]
  def colours(%{effect: :off}), do: []
  def colours(setting), do: colours(setting.palette, setting.hue)

  @doc "Milliseconds per cycle for a speed step."
  @spec period(1..10) :: pos_integer
  def period(speed), do: elem(@periods, clamp(speed, 1, 10) - 1)

  @doc "The request that makes the `leds` driver show a setting."
  @spec command(map) :: tuple
  def command(%{effect: :off}), do: {:effect, :off, [], []}

  def command(setting) do
    {:effect, setting.effect, colours(setting.palette, setting.hue),
     [
       period: period(setting.speed),
       brightness: setting.brightness,
       spread: setting.spread,
       direction: if(setting.direction == :ccw, do: 1, else: 0),
       trail: setting.trail,
       density: setting.density
     ]}
  end

  @doc "The request that flashes the whole ring in a hue for `ms`, over whatever is running."
  @spec flash(non_neg_integer, pos_integer) :: tuple
  def flash(hue, ms \\ @flash_ms), do: {:flash, Color.rgb888(Color.hsv_to_rgb(hue, 255, 255)), ms}

  @doc "A setting as it is written to NVS."
  @spec encode(map) :: binary
  def encode(setting) do
    :erlang.atom_to_binary(setting.effect) <>
      " pal=" <>
      :erlang.atom_to_binary(setting.palette) <>
      " hue=" <>
      int(setting.hue) <>
      " spd=" <>
      int(setting.speed) <>
      " bri=" <>
      int(setting.brightness) <>
      " spr=" <>
      int(setting.spread) <>
      " dir=" <>
      :erlang.atom_to_binary(setting.direction) <>
      " trl=" <> int(setting.trail) <> " den=" <> int(setting.density)
  end

  @doc "A setting read back from NVS; anything absent or corrupt reads as its default."
  @spec decode(binary | nil) :: map
  def decode(nil), do: @default
  def decode("dusk"), do: %{@default | effect: :drift, palette: :dusk}
  def decode("white"), do: %{@default | effect: :solid, palette: :white, spread: 0}
  def decode(<<"solid:", hue::binary>>), do: solid(number(hue, 0, 359))

  def decode(stored) do
    case :binary.split(stored, " ", [:global]) do
      [name | fields] -> :lists.foldl(&field/2, %{@default | effect: effect(name)}, fields)
    end
  end

  defp solid(:error), do: @default
  defp solid(hue), do: %{@default | effect: :solid, palette: :hue, hue: hue, spread: 0}

  defp effect(name) do
    case named(effects(), name) do
      nil -> @default.effect
      effect -> effect
    end
  end

  defp field(<<"pal=", name::binary>>, setting),
    do: put(setting, :palette, named(palettes(), name))

  defp field(<<"hue=", n::binary>>, setting), do: put(setting, :hue, number(n, 0, 359))
  defp field(<<"spd=", n::binary>>, setting), do: put(setting, :speed, number(n, 1, 10))
  defp field(<<"bri=", n::binary>>, setting), do: put(setting, :brightness, number(n, 0, 100))
  defp field(<<"spr=", n::binary>>, setting), do: put(setting, :spread, number(n, 0, 100))
  defp field(<<"dir=", d::binary>>, setting), do: put(setting, :direction, named([:cw, :ccw], d))
  defp field(<<"trl=", n::binary>>, setting), do: put(setting, :trail, number(n, 0, 100))
  defp field(<<"den=", n::binary>>, setting), do: put(setting, :density, number(n, 0, 100))
  defp field(_other, setting), do: setting

  defp put(setting, _key, nil), do: setting
  defp put(setting, _key, :error), do: setting
  defp put(setting, key, value), do: Map.put(setting, key, value)

  defp named([], _name), do: nil

  defp named([atom | rest], name) do
    case :erlang.atom_to_binary(atom) == name do
      true -> atom
      false -> named(rest, name)
    end
  end

  defp find([], _key, fallback), do: fallback
  defp find([{key, value} | _rest], key, _fallback), do: value
  defp find([_entry | rest], key, fallback), do: find(rest, key, fallback)

  defp number(binary, low, high) do
    case digits(binary, 0, false) do
      n when is_integer(n) and n >= low and n <= high -> n
      _other -> :error
    end
  end

  # Anything that is not all digits is a corrupt value, not a small number.
  defp digits(<<>>, _acc, false), do: :error
  defp digits(<<>>, acc, true), do: acc

  defp digits(<<digit, rest::binary>>, acc, _any) when digit >= ?0 and digit <= ?9 do
    digits(rest, acc * 10 + (digit - ?0), true)
  end

  defp digits(_binary, _acc, _any), do: :error

  defp int(n), do: :erlang.integer_to_binary(n)

  defp clamp(n, low, _high) when n < low, do: low
  defp clamp(n, _low, high) when n > high, do: high
  defp clamp(n, _low, _high), do: n
end
