defmodule Badge.Page.Snake do
  @moduledoc """
  Snake on the whole panel, steered with the arrow keys, or Z, Ctrl, SP and Alt for up, left, down
  and right.

  The title screen shows the best score and Enter starts a game. In a game
  Escape goes back to the title screen; after one, Enter plays again. The
  best score is kept in NVS under `snake` as one big-endian 16-bit count.

  Colours come from the active skin. The background is the skin's own when
  it is dark and black otherwise, and any colour too dim to read on it is
  swapped for a light one.
  """

  use Badge.Page

  alias Badge.Nvs
  alias Badge.Pixels
  alias Badge.Snake
  alias Badge.Theme

  @eat {120, 400}
  @lose {0, 2000}

  @x0 5
  @y0 25
  @cell 10

  @impl true
  def title, do: "Snake"

  @impl true
  def chrome?(_state), do: false

  @impl true
  def init, do: %{screen: :title, best: nil, game: nil, due: 0}

  @impl true
  def handle_key({:edit, :newline}, %{screen: screen} = state) when screen != :play,
    do: {:ok, %{state | screen: :play, game: nil}}

  def handle_key({:nav, :home}, %{screen: screen} = state) when screen != :title,
    do: {:ok, %{state | screen: :title}}

  def handle_key(event, %{screen: :play, game: %{} = game} = state) do
    case key_dir(event) do
      nil -> :ignore
      dir -> {:ok, %{state | game: Snake.turn(game, Snake.dir(dir))}}
    end
  end

  def handle_key(_event, _state), do: :ignore

  defp key_dir({:move, dir}), do: dir
  defp key_dir({:char, char}) when char == ?z or char == ?Z, do: :up
  defp key_dir({:mod, :ctrl}), do: :left
  defp key_dir({:mod, :solder}), do: :down
  defp key_dir({:mod, :alt}), do: :right
  defp key_dir(_event), do: nil

  # Hardware is only touched here, never from a key handler.
  @impl true
  def tick(%{best: nil} = state), do: tick(%{state | best: decode(Nvs.get(:snake))})

  def tick(%{best: best} = state) do
    next = advance(state, :erlang.monotonic_time(:millisecond))

    case cue(state, next) do
      {hue, ms} -> Pixels.flash(hue, ms)
      nil -> :ok
    end

    case next do
      %{best: ^best} ->
        next

      %{best: record} ->
        _ = Nvs.put(:snake, encode(record))
        next
    end
  end

  @doc "The LED flash a step calls for: green on eating, red on losing, or nil."
  def cue(%{screen: :play}, %{screen: :over}), do: @lose

  def cue(%{screen: :play, game: %{score: score}}, %{screen: :play, game: %{score: more}})
      when more > score,
      do: @eat

  def cue(_before, _after), do: nil

  @doc """
  Moves the game on to monotonic time `now`.

  A state with nothing due comes back unchanged, so nothing is redrawn.
  """
  def advance(%{screen: :play, game: nil} = state, now),
    do: %{state | game: Snake.new(now, 31, 21), due: now + Snake.interval(%{score: 0})}

  def advance(%{screen: :play, due: due} = state, now) when now < due, do: state

  def advance(%{screen: :play, due: due, game: game, best: best} = state, now) do
    game = Snake.step(game)
    interval = Snake.interval(game)

    case game do
      %{over: true, score: score} ->
        %{state | game: game, screen: :over, best: max(best, score)}

      _playing ->
        %{state | game: game, due: max(due, now - interval) + interval}
    end
  end

  def advance(state, _now), do: state

  @doc "The NVS value for a best score."
  def encode(best), do: <<best::16>>

  @doc "The best score from its NVS value, or from an older one with two counts; anything else is 0."
  def decode(<<best::16>>), do: best
  def decode(<<keys::16, _tilt::16>>), do: keys
  def decode(_value), do: 0

  @impl true
  def render(state) do
    bg = background()
    render(state, bg, light(Theme.fg(), 0xFFFFFF), light(Theme.muted(), 0xAAAAAA))
  end

  defp render(%{screen: :title} = state, bg, fg, muted) do
    [
      {:text, 120, 80, :dogica, fg, bg, "SNAKE"},
      {:text, 124, 120, :default16px, muted, bg, "Best " <> pad(best(state))},
      {:text, 108, 160, :default16px, muted, bg, "Enter to play"}
    ] ++ field(bg)
  end

  defp render(%{screen: :over, game: %{score: score}} = state, bg, fg, muted) do
    [
      {:text, 88, 76, :dogica, fg, bg, "GAME OVER"},
      {:text, 120, 104, :default16px, fg, bg, "Score " <> pad(score)},
      {:text, 120, 124, :default16px, muted, bg, "Best  " <> pad(best(state))},
      {:text, 72, 148, :default16px, muted, bg, "Enter again  Esc title"}
    ] ++ score(score, state, bg, fg, muted) ++ field(bg)
  end

  defp render(%{game: nil} = state, bg, fg, muted),
    do: score(0, state, bg, fg, muted) ++ field(bg)

  defp render(%{game: %{body: body, food: food, score: score}} = state, bg, fg, muted) do
    snake = light(Theme.accent(), 0xC0C0C0)
    eaten = light(Theme.alert(), 0xFF5050)

    body(Snake.runs(body), snake, []) ++
      head(body, light(Theme.select(), 0xFFFFFF)) ++
      food(food, eaten) ++ score(score, state, bg, fg, muted) ++ field(bg)
  end

  defp head([{col, row} | _], colour),
    do: [{:rect, @x0 + @cell * col, @y0 + @cell * row, @cell - 1, @cell - 1, colour}]

  defp body([], _colour, acc), do: :lists.reverse(acc)

  defp body([{{c1, r1}, {c2, r2}} | runs], colour, acc) do
    rect =
      {:rect, @x0 + @cell * min(c1, c2), @y0 + @cell * min(r1, r2),
       @cell * (abs(c1 - c2) + 1) - 1, @cell * (abs(r1 - r2) + 1) - 1, colour}

    body(runs, colour, [rect | acc])
  end

  defp food(nil, _colour), do: []

  defp food({col, row}, colour),
    do: [{:rect, @x0 + @cell * col + 2, @y0 + @cell * row + 2, 5, 5, colour}]

  defp score(score, state, bg, fg, muted),
    do: [
      {:text, 4, 3, :default16px, fg, bg, pad(score)},
      {:text, 260, 3, :default16px, muted, bg, "HI " <> pad(best(state))}
    ]

  defp best(%{best: best}) when is_integer(best), do: best
  defp best(_state), do: 0

  # The playfield's frame and the whole-panel background, which goes last.
  defp field(bg) do
    [
      {:rect, 4, 24, 311, 211, bg},
      {:rect, 2, 22, 315, 215, light(Theme.dim(), 0x808080)},
      {:rect, 0, 0, 320, 240, bg}
    ]
  end

  defp background do
    case brightness(Theme.bg()) < 96 do
      true -> Theme.bg()
      false -> 0x000000
    end
  end

  # The colour when it is bright enough to read on black, else `fallback`.
  defp light(colour, fallback) do
    case brightness(colour) >= 96 do
      true -> colour
      false -> fallback
    end
  end

  defp brightness(colour) do
    div(
      2 * div(colour, 0x10000) + 5 * rem(div(colour, 0x100), 0x100) + rem(colour, 0x100),
      8
    )
  end

  defp pad(n) do
    digits = :erlang.integer_to_binary(n)

    case byte_size(digits) do
      size when size < 4 -> :binary.copy("0", 4 - size) <> digits
      _size -> digits
    end
  end
end
