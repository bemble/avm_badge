defmodule Badge.KeymapTest do
  use ExUnit.Case, async: true

  alias Badge.Keymap

  describe "letters" do
    test "unshifted letters are lowercase" do
      assert Keymap.decode(~c"Q", false) == {:char, ?q}
      assert Keymap.decode(~c"A", false) == {:char, ?a}
      assert Keymap.decode(~c"Z", false) == {:char, ?z}
    end

    test "shifted letters are uppercase" do
      assert Keymap.decode(~c"Q", true) == {:char, ?Q}
      assert Keymap.decode(~c"M", true) == {:char, ?M}
    end
  end

  describe "number row" do
    test "unshifted digits" do
      assert Keymap.decode(~c"1", false) == {:char, ?1}
      assert Keymap.decode(~c"0", false) == {:char, ?0}
    end

    test "shifted digits give the US symbol row" do
      assert Keymap.decode(~c"1", true) == {:char, ?!}
      assert Keymap.decode(~c"2", true) == {:char, ?@}
      assert Keymap.decode(~c"3", true) == {:char, ?#}
      assert Keymap.decode(~c"4", true) == {:char, ?$}
      assert Keymap.decode(~c"5", true) == {:char, ?%}
      assert Keymap.decode(~c"6", true) == {:char, ?^}
      assert Keymap.decode(~c"7", true) == {:char, ?&}
      assert Keymap.decode(~c"8", true) == {:char, ?*}
      assert Keymap.decode(~c"9", true) == {:char, ?(}
      assert Keymap.decode(~c"0", true) == {:char, ?)}
    end
  end

  describe "punctuation pairs" do
    test "every pair maps both ways" do
      pairs = [
        {~c"`", ?`, ?~},
        {~c"-", ?-, ?_},
        {~c"=", ?=, ?+},
        {~c"[", ?[, ?{},
        {~c"]", ?], ?}},
        {~c"\\", ?\\, ?|},
        {~c";", ?;, ?:},
        {~c"'", ?', ?"},
        {~c",", ?,, ?<},
        {~c".", ?., ?>},
        {~c"/", ?/, ??}
      ]

      for {label, unshifted, shifted} <- pairs do
        assert Keymap.decode(label, false) == {:char, unshifted}
        assert Keymap.decode(label, true) == {:char, shifted}
      end
    end
  end

  describe "space" do
    test "is an ordinary printable character in both states" do
      assert Keymap.decode(~c"Space", false) == {:char, ?\s}
      assert Keymap.decode(~c"Space", true) == {:char, ?\s}
    end
  end

  describe "edit keys" do
    test "map to edit operations regardless of shift" do
      assert Keymap.decode(~c"Bksp", false) == {:edit, :backspace}
      assert Keymap.decode(~c"Bksp", true) == {:edit, :backspace}
      assert Keymap.decode(~c"Enter", false) == {:edit, :newline}
      assert Keymap.decode(~c"Tab", false) == {:edit, :tab}
    end
  end

  describe "navigation keys" do
    test "escape goes home" do
      assert Keymap.decode(~c"Esc", false) == {:nav, :home}
    end

    test "each shape key names its own slot" do
      assert Keymap.decode(~c"Square", false) == {:nav, :square}
      assert Keymap.decode(~c"Triangle", false) == {:nav, :triangle}
      assert Keymap.decode(~c"Cross", false) == {:nav, :cross}
      assert Keymap.decode(~c"Circle", false) == {:nav, :circle}
      assert Keymap.decode(~c"Clover", false) == {:nav, :clover}
      assert Keymap.decode(~c"Diamond", false) == {:nav, :diamond}
    end

    test "shift does not change navigation" do
      assert Keymap.decode(~c"Esc", true) == {:nav, :home}
      assert Keymap.decode(~c"Square", true) == {:nav, :square}
    end
  end

  describe "arrow keys" do
    test "arrows are movement, not navigation" do
      assert Keymap.decode(~c"Up", false) == {:move, :up}
      assert Keymap.decode(~c"Down", false) == {:move, :down}
      assert Keymap.decode(~c"Left", false) == {:move, :left}
      assert Keymap.decode(~c"Right", false) == {:move, :right}
    end

    test "shift does not change movement" do
      assert Keymap.decode(~c"Up", true) == {:move, :up}
    end
  end

  describe "free modifier keys" do
    test "Ctrl, SP and left Alt decode to mod events, shifted or not" do
      for shifted <- [false, true] do
        assert Keymap.decode(~c"Ctrl", shifted) == {:mod, :ctrl}
        assert Keymap.decode(~c"SP", shifted) == {:mod, :solder}
        assert Keymap.decode(~c"Alt", shifted) == {:mod, :alt}
      end
    end
  end

  describe "keys with no meaning" do
    test "modifiers and unmapped intersections are ignored, shifted or not" do
      for label <- [
            ~c"LShift",
            ~c"RShift",
            ~c"AltGr",
            ~c"Fn",
            ~c"<unmapped R0C0>"
          ] do
        assert Keymap.decode(label, false) == :ignore
        assert Keymap.decode(label, true) == :ignore
      end
    end
  end
end
