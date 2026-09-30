defmodule Badge.SkinTest do
  use ExUnit.Case, async: true

  alias Badge.Skin
  alias Badge.Skin.Dark
  alias Badge.Skin.Macintosh
  alias Badge.Skin.NabuCasa
  alias Badge.Skin.NeonDusk
  alias Badge.Skin.Win95
  alias Badge.Skin.WinXP
  alias Badge.Theme

  @status %{battery: :battery_100, wifi: :wifi, clock: "12:34"}

  defp palette(skin) do
    [
      skin.bg(),
      skin.fg(),
      skin.muted(),
      skin.dim(),
      skin.accent(),
      skin.ok(),
      skin.warn(),
      skin.alert(),
      skin.select()
    ]
  end

  describe "decorations" do
    test "only the neon skins have any, a chaser round the edge among them" do
      assert Dark.decor() == []
      assert Win95.decor() == []
      assert Macintosh.decor() == []
      assert Enum.any?(NeonDusk.decor(), &match?({:chaser, _, _, _, _, _}, &1))
      assert Enum.any?(NabuCasa.decor(), &match?({:chaser, _, _, _, _, _}, &1))
    end

    test "NabuCasa has no beam and no glitches" do
      kinds = for spec <- NabuCasa.decor(), do: elem(spec, 0)

      assert :lists.usort(kinds) == [:chaser, :line]
    end

    test "NabuCasa wears the brand colours" do
      assert NabuCasa.muted() == 0xA8B7CD
      assert NabuCasa.select() == 0xFFDE77
      assert {:rect, 10, 5, 4, 1, 0xFFDE77} in NabuCasa.chrome("Badge", @status)
      assert NabuCasa.chrome("Badge", @status) != NeonDusk.chrome("Badge", @status)
    end

    test "a page gets lines only with its title bar, and a border only if it asks" do
      kinds = fn chrome?, border? ->
        for spec <- Skin.decor(NeonDusk, chrome?, border?), do: elem(spec, 0)
      end

      assert :lists.usort(kinds.(true, false)) == [:beam, :glitch, :line]
      assert :lists.usort(kinds.(false, true)) == [:beam, :chaser, :glitch]
      assert :lists.usort(kinds.(false, false)) == [:beam, :glitch]
      assert Skin.decor(Dark, true, true) == []
    end

    test "Neon Dusk's horizon pulses where the chrome draws it" do
      lines = for {:line, _, y, _, h, _, :pulse, _, _} <- NeonDusk.decor(), do: {y, h}

      assert lines == [{Theme.bar_h(), 2}, {Theme.bar_h() + 2, 1}]
    end
  end

  describe "the list" do
    test "starts with the default" do
      assert hd(Skin.all()) == Skin.default()
    end

    test "every skin has a distinct name" do
      names = for skin <- Skin.all(), do: skin.name()

      assert length(names) == length(:lists.usort(names))
    end

    test "shift stops at both ends rather than wrapping" do
      assert Skin.shift(Dark, -1) == Dark
      assert Skin.shift(Dark, 1) == Win95
      assert Skin.shift(Win95, 1) == WinXP
      assert Skin.shift(WinXP, 1) == Macintosh
      assert Skin.shift(Macintosh, 1) == NeonDusk
      assert Skin.shift(NeonDusk, 1) == NabuCasa
      assert Skin.shift(NabuCasa, 1) == NabuCasa
      assert Skin.shift(Macintosh, -1) == WinXP
    end
  end

  describe "the active skin" do
    test "is the default until one is activated" do
      assert Skin.current() == Dark
      assert Theme.fg() == Dark.fg()
    end

    test "changes what the theme answers" do
      Skin.activate(Win95)

      assert Skin.current() == Win95
      assert Theme.bg() == Win95.bg()
      assert Theme.select() == Win95.select()
      assert Theme.rule(0, 10, 100) == Win95.rule(0, 10, 100)
    end
  end

  describe "storage" do
    test "decodes a name back to its skin" do
      for skin <- Skin.all() do
        assert Skin.decode(skin.name()) == skin
      end
    end

    test "falls back to the default for nothing or nonsense" do
      assert Skin.decode(nil) == Skin.default()
      assert Skin.decode("Aqua") == Skin.default()
    end
  end

  describe "the Macintosh title bar" do
    @long %{battery: :battery_100, wifi: :wifi, clock: "12:34:56 UTC"}

    test "is drawn in black and white only" do
      for item <- Macintosh.chrome("Badge", @long) do
        case item do
          {:rect, _x, _y, _w, _h, colour} -> assert colour in [0x000000, 0xFFFFFF]
          {:text, _x, _y, _f, fg, bg, _b} -> assert {fg, bg} == {0x000000, 0xFFFFFF}
          {:image, _x, _y, bg, _image} -> assert bg == 0xFFFFFF
        end
      end
    end

    test "keeps the longest title clear of the longest clock and the close box" do
      items = Macintosh.chrome("Sudo Mode", @long)
      [clock_x] = for {:text, x, _y, :default16px, _fg, _bg, _b} <- items, do: x
      [{title_x, title}] = for {:text, x, _y, :pixel_operator, _fg, _bg, b} <- items, do: {x, b}

      assert title_x + Badge.Font.width(:pixel_operator, title) < clock_x
      assert title_x > 24
    end
  end

  for skin <- [Dark, Win95, WinXP, Macintosh, NeonDusk, NabuCasa] do
    describe "#{inspect(skin)}" do
      @skin skin

      test "every colour fits in 24 bits" do
        for colour <- palette(@skin) do
          assert colour >= 0x000000
          assert colour <= 0xFFFFFF
        end
      end

      test "colours are distinct" do
        colours = palette(@skin)

        assert length(colours) == length(:lists.usort(colours))
      end

      test "chrome ends with a full-panel background in its own colour" do
        assert :lists.last(@skin.chrome("Badge", @status)) ==
                 {:rect, 0, 0, Theme.width(), Theme.height(), @skin.bg()}
      end

      test "chrome carries the title, the clock and both icons" do
        items = @skin.chrome("Badge", @status)
        bodies = for {:text, _x, _y, _f, _fg, _bg, body} <- items, do: body
        icons = for {:image, _x, _y, _bg, _image} <- items, do: :icon

        assert "Badge" in bodies
        assert "12:34" in bodies
        assert length(icons) == 2
      end

      test "chrome icons are drawn in a baked tint" do
        for {:image, _x, _y, _bg, {:rgba8888, _w, _h, binary}} <- @skin.chrome("Badge", @status) do
          assert is_binary(binary)
        end
      end

      test "glyph colour is one the icons are baked in" do
        assert @skin.glyph() in Badge.Icons.tints()
      end

      test "chrome stays inside the title bar" do
        items = :lists.droplast(@skin.chrome("Badge", @status))

        for item <- items do
          bottom =
            case item do
              {:rect, _x, y, _w, h, _c} -> y + h
              {:text, _x, y, _f, _fg, _bg, _b} -> y + 16
              {:image, _x, y, _bg, {:rgba8888, _w, h, _d}} -> y + h
            end

          assert bottom <= Theme.content_top()
        end
      end

      test "decorations are specs the LVGL driver reads" do
        for spec <- @skin.decor() do
          case spec do
            {:border, thickness, speed, colours} ->
              assert thickness in 1..8 and speed >= 0
              assert length(colours) in 1..8
              assert Enum.all?(colours, &(&1 in 0..0xFFFFFF))

            {:chaser, thickness, speed, length, trail, colours} ->
              assert thickness in 1..8 and speed > 0 and length > 0 and trail >= 0
              assert length(colours) in 1..8
              assert Enum.all?(colours, &(&1 in 0..0xFFFFFF))

            {:beam, colour, period, height, opacity} ->
              assert colour in 0..0xFFFFFF and period > 0 and height in 1..16 and
                       opacity in 0..255

            {:glitch, colours, min_ms, max_ms} ->
              assert length(colours) in 1..8 and min_ms > 0 and max_ms >= min_ms

            {:line, x, y, w, h, colours, mode, period, floor} ->
              assert x >= 0 and y >= 0 and x + w <= Theme.width() and y + h <= Theme.height()
              assert length(colours) in 1..8 and Enum.all?(colours, &(&1 in 0..0xFFFFFF))
              assert mode in [:pulse, :flow] and period > 0 and floor in 0..100
          end
        end
      end

      test "a rule is one or more single-row rects spanning the width asked for" do
        items = @skin.rule(8, 100, 200)

        assert length(items) >= 1

        for {:rect, x, _y, w, h, _c} <- items do
          assert x == 8
          assert w == 200
          assert h == 1
        end
      end
    end
  end
end
