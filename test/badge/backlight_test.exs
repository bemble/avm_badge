defmodule Badge.BacklightTest do
  use ExUnit.Case, async: true

  alias Badge.Backlight

  describe "stored settings" do
    test "nothing saved gives the defaults" do
      assert Backlight.decode_brightness(nil) == 100
      assert Backlight.decode_sleep(nil) == :s30
      assert Backlight.decode_motion(nil) == false
    end

    test "wake on motion round-trips through storage" do
      for motion <- [true, false] do
        assert Backlight.decode_motion(Backlight.motion_label(motion)) == motion
      end
    end

    test "an unknown wake on motion value falls back to off" do
      assert Backlight.decode_motion("banana") == false
      assert Backlight.decode_motion("") == false
    end

    test "a saved brightness comes back" do
      assert Backlight.decode_brightness("45") == 45
      assert Backlight.decode_brightness("5") == 5
      assert Backlight.decode_brightness("100") == 100
    end

    test "a corrupt or out-of-range brightness falls back rather than crashing" do
      for stored <- ["", "abc", "45x", "-10", "0", "101", "99999"] do
        assert Backlight.decode_brightness(stored) == 100
      end
    end

    test "every sleep option round-trips through storage" do
      for {name, _label} <- Backlight.timeouts() do
        assert Backlight.decode_sleep(Backlight.sleep_label(name)) == name
      end
    end

    test "an unknown sleep value falls back to the default" do
      assert Backlight.decode_sleep("banana") == :s30
      assert Backlight.decode_sleep("") == :s30
    end

    test "the options are the ones the page offers, in order" do
      labels = for {_name, label} <- Backlight.timeouts(), do: label

      assert labels == ["10s", "30s", "60s", "off"]
    end
  end

  describe "duty/1" do
    test "full brightness holds the pin low, which is no duty at all" do
      assert Backlight.duty(100) == 0
    end

    test "dark is full duty, since the pin is active low" do
      assert Backlight.duty(0) == 1024
    end

    test "dark is the whole cycle, so the panel is not faintly lit" do
      # LEDC counts 0..2^resolution inclusive; one short of that still lets light through.
      assert Backlight.duty(0) == :math.pow(2, 10) |> round()
    end

    test "no brightness setting is as dark as off" do
      for percent <- 1..100 do
        assert Backlight.duty(percent) < Backlight.duty(0)
      end
    end

    test "brighter always means less duty" do
      duties = for percent <- 0..100, do: Backlight.duty(percent)

      assert duties == :lists.reverse(:lists.sort(duties))
    end

    test "half brightness is well below half light, because the curve is not linear" do
      # Duty is inverted, so more duty means less light.
      assert Backlight.duty(50) > 700
    end

    test "follows a square law, so the dial feels even to the eye" do
      lit = fn percent -> 1023 - Backlight.duty(percent) end

      assert lit.(50) == 255
      assert lit.(70) == 501
      assert lit.(100) == 1023
    end

    test "the lowest setting is far dimmer than a whole percent could express" do
      lit = 1023 - Backlight.duty(5)

      assert lit < 10
      assert lit > 0
    end

    test "never goes fully dark, so the dial can always be found again" do
      for percent <- 1..100 do
        assert Backlight.duty(percent) < 1023
      end
    end

    test "the steps grow as the setting rises, which is the point of the curve" do
      steps =
        for percent <- 10..90//10 do
          Backlight.duty(percent) - Backlight.duty(percent + 10)
        end

      assert steps == :lists.sort(steps)
      assert hd(steps) < :lists.last(steps)
    end

    test "never leaves the range the timer can express" do
      # A 10 bit timer counts 0..1024 inclusive, 1024 being the whole cycle.
      for percent <- -20..120 do
        duty = Backlight.duty(percent)

        assert duty >= 0
        assert duty <= 1024
      end
    end

    test "clamps rather than wrapping past the ends" do
      assert Backlight.duty(150) == Backlight.duty(100)
      assert Backlight.duty(-50) == Backlight.duty(0)
    end
  end

  describe "sleep_ticks/2" do
    test "converts each timeout into ticks of the base interval" do
      assert Backlight.sleep_ticks(:s10, 100) == 100
      assert Backlight.sleep_ticks(:s30, 100) == 300
      assert Backlight.sleep_ticks(:s60, 100) == 600
    end

    test "off never sleeps" do
      assert Backlight.sleep_ticks(:off, 100) == :never
    end

    test "an unknown setting is treated as the default rather than never" do
      assert Backlight.sleep_ticks(:nonsense, 100) ==
               Backlight.sleep_ticks(Backlight.default_sleep(), 100)
    end

    test "a slower base tick needs fewer of them" do
      assert Backlight.sleep_ticks(:s30, 500) == 60
    end
  end
end
