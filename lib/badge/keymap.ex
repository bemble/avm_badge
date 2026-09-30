defmodule Badge.Keymap do
  @moduledoc """
  Translates a physical key label from `Badge.Keyboard` into an editing intent.

  US-QWERTY. The keyboard matrix reports labels (`~c"Q"`, `~c"LShift"`,
  `~c"Space"`), not characters, so this is the layer that decides what a key
  actually means. Keys with no text meaning — modifiers, arrows, the badge's
  shape keys — return `:ignore` rather than being silently dropped upstream,
  so the caller has one place to look when a key does nothing. Ctrl, SP and
  left Alt decode to `{:mod, :ctrl | :solder | :alt}`, which pages may bind.

  The lookup tables are built at compile time on the host, where the full
  Elixir standard library is available. Only `decode/2` runs on AtomVM.
  """

  # {label, unshifted, shifted}
  @punctuation [
    {~c"`", ?`, ?~},
    {~c"1", ?1, ?!},
    {~c"2", ?2, ?@},
    {~c"3", ?3, ?#},
    {~c"4", ?4, ?$},
    {~c"5", ?5, ?%},
    {~c"6", ?6, ?^},
    {~c"7", ?7, ?&},
    {~c"8", ?8, ?*},
    {~c"9", ?9, ?(},
    {~c"0", ?0, ?)},
    {~c"-", ?-, ?_},
    {~c"=", ?=, ?+},
    {~c"[", ?[, ?{},
    {~c"]", ?], ?}},
    {~c"\\", ?\\, ?|},
    {~c";", ?;, ?:},
    {~c"'", ?', ?"},
    {~c",", ?,, ?<},
    {~c".", ?., ?>},
    {~c"/", ?/, ??},
    {~c"Space", ?\s, ?\s}
  ]

  # The layout labels letters in uppercase; unshifted typing is lowercase.
  @letters for c <- ?A..?Z, do: {[c], c + 32, c}

  @printable @punctuation ++ @letters

  @unshifted for {label, unshifted, _shifted} <- @printable,
                 into: %{},
                 do: {label, unshifted}

  @shifted for {label, _unshifted, shifted} <- @printable,
               into: %{},
               do: {label, shifted}

  @edits %{
    ~c"Bksp" => :backspace,
    ~c"Enter" => :newline,
    ~c"Tab" => :tab
  }

  # Handled by Badge.UI before a page ever sees them.
  @nav %{
    ~c"Esc" => :home,
    ~c"Square" => :square,
    ~c"Triangle" => :triangle,
    ~c"Cross" => :cross,
    ~c"Circle" => :circle,
    ~c"Clover" => :clover,
    ~c"Diamond" => :diamond
  }

  # Passed through to the current page.
  @moves %{
    ~c"Up" => :up,
    ~c"Down" => :down,
    ~c"Left" => :left,
    ~c"Right" => :right
  }

  # Free keys a page may bind; text fields ignore them.
  @mods %{
    ~c"Ctrl" => :ctrl,
    ~c"SP" => :solder,
    ~c"Alt" => :alt
  }

  @doc """
  Decodes a key label into an editing intent.

  `shifted` is whether either shift key was held at the moment this key was
  pressed. Anything with no text meaning returns `:ignore`.
  """
  def decode(label, shifted) do
    table = if shifted, do: @shifted, else: @unshifted

    case Map.get(table, label) do
      nil -> edit(label)
      char -> {:char, char}
    end
  end

  defp edit(label) do
    case Map.get(@edits, label) do
      nil -> nav(label)
      op -> {:edit, op}
    end
  end

  defp nav(label) do
    case Map.get(@nav, label) do
      nil -> move(label)
      key -> {:nav, key}
    end
  end

  defp move(label) do
    case Map.get(@moves, label) do
      nil -> mod(label)
      dir -> {:move, dir}
    end
  end

  defp mod(label) do
    case Map.get(@mods, label) do
      nil -> :ignore
      key -> {:mod, key}
    end
  end
end
