defmodule Badge.LedEffectTest do
  use ExUnit.Case, async: true

  alias Badge.LedEffect

  @default LedEffect.default()

  describe "the effects" do
    test "every effect but off names the options it uses" do
      for effect <- LedEffect.effects(), effect != :off do
        assert LedEffect.options(effect) != []
      end

      assert LedEffect.options(:off) == []
    end

    test "every option an effect names is a field of a setting" do
      for effect <- LedEffect.effects(), option <- LedEffect.options(effect) do
        assert Map.has_key?(@default, option)
      end
    end

    test "rainbow is the default and ignores the palette" do
      assert @default.effect == :rainbow
      refute :palette in LedEffect.options(:rainbow)
    end
  end

  describe "palettes" do
    test "every palette has one to eight 24-bit colours" do
      for palette <- LedEffect.palettes() do
        colours = LedEffect.colours(palette, 120)

        assert length(colours) in 1..8
        assert Enum.all?(colours, &(&1 in 0..0xFFFFFF))
      end
    end

    test "the hue palette is the one colour its hue names" do
      assert LedEffect.colours(:hue, 0) == [0xFF0000]
      assert LedEffect.colours(:hue, 120) == [0x00FF00]
    end
  end

  describe "command/1" do
    test "carries the effect, its colours and every option" do
      setting = %{@default | effect: :chase, palette: :fire, speed: 10, direction: :ccw}

      assert {:effect, :chase, [0xFFB040, 0xFF6A00, 0xFF2000], opts} = LedEffect.command(setting)
      assert opts[:period] == 400
      assert opts[:direction] == 1
      assert opts[:brightness] == @default.brightness
    end

    test "off sends nothing to show" do
      assert LedEffect.command(%{@default | effect: :off}) == {:effect, :off, [], []}
    end

    test "speed runs from slow to fast" do
      assert LedEffect.period(1) > LedEffect.period(5)
      assert LedEffect.period(5) > LedEffect.period(10)
    end

    test "a flash is one colour held briefly" do
      assert {:flash, 0xFF0000, ms} = LedEffect.flash(0)
      assert ms in 100..2000
    end

    test "a flash can be held for a given time" do
      assert {:flash, 0x00FF00, 1500} = LedEffect.flash(120, 1500)
    end
  end

  describe "storage" do
    test "a setting survives a round trip" do
      setting = %{
        @default
        | effect: :twinkle,
          palette: :hue,
          hue: 285,
          speed: 8,
          brightness: 65,
          spread: 20,
          direction: :ccw,
          trail: 90,
          density: 10
      }

      assert LedEffect.decode(LedEffect.encode(setting)) == setting
    end

    test "is readable text" do
      assert LedEffect.encode(@default) =~ "rainbow pal=neon"
    end

    test "nothing stored reads as the default" do
      assert LedEffect.decode(nil) == @default
    end

    test "a corrupt field keeps its default and the rest" do
      decoded = LedEffect.decode("chase spd=99 bri=x pal=plaid trl=70 junk")

      assert decoded.effect == :chase
      assert decoded.speed == @default.speed
      assert decoded.brightness == @default.brightness
      assert decoded.palette == @default.palette
      assert decoded.trail == 70
    end

    test "an unknown effect reads as the default one" do
      assert LedEffect.decode("disco").effect == @default.effect
    end

    test "modes saved by older firmware read as their nearest effect" do
      assert LedEffect.decode("rainbow").effect == :rainbow
      assert LedEffect.decode("off").effect == :off
      assert %{effect: :drift, palette: :dusk} = LedEffect.decode("dusk")
      assert %{effect: :solid, palette: :white} = LedEffect.decode("white")
      assert %{effect: :solid, palette: :hue, hue: 120} = LedEffect.decode("solid:120")
      assert LedEffect.decode("solid:999") == @default
    end
  end
end
