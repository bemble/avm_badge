defmodule Badge.Snake do
  @moduledoc """
  The rules of Snake on a grid of cells, as plain data.

  `new/3` lays a four-cell snake across the middle heading right, `turn/2`
  buffers one turn for the next `step/1`, and `step/1` moves, eats, grows
  and ends the game on a wall or the snake's own body. The body is a list
  of `{col, row}` cells, head first, and a direction is the `{dcol, drow}`
  of one step, so `{0, -1}` is up.

  `runs/1` folds the body into straight runs for drawing.
  """

  @start_ms 200
  @speedup_ms 4
  @floor_ms 100

  @type cell :: {integer, integer}
  @type dir :: {-1..1, -1..1}

  @doc "A new game on a `cols` x `rows` grid, food placed from `seed`."
  @spec new(integer, pos_integer, pos_integer) :: map
  def new(seed, cols, rows) do
    row = div(rows, 2)
    col = div(cols, 2)

    feed(%{
      cols: cols,
      rows: rows,
      body: [{col, row}, {col - 1, row}, {col - 2, row}, {col - 3, row}],
      dir: {1, 0},
      next: {1, 0},
      food: nil,
      seed: rem(abs(seed), 2_147_483_648),
      score: 0,
      over: false
    })
  end

  @doc "The direction an arrow key names."
  @spec dir(atom) :: dir
  def dir(:up), do: {0, -1}
  def dir(:down), do: {0, 1}
  def dir(:left), do: {-1, 0}
  def dir(:right), do: {1, 0}

  @doc "Buffers a turn for the next step; a reversal or a second turn is ignored."
  @spec turn(map, dir) :: map
  def turn(%{dir: {dc, dr} = dir, next: dir} = game, {tc, tr} = to) do
    case {dc + tc, dr + tr} do
      {0, 0} -> game
      _turned -> %{game | next: to}
    end
  end

  def turn(game, _to), do: game

  @doc "Moves one cell; eating grows the snake, a wall or its body ends the game."
  @spec step(map) :: map
  def step(%{body: [{col, row} | _] = body, next: {dc, dr} = dir, food: food} = game) do
    cell = {col + dc, row + dr}
    eats = cell == food
    rest = if eats, do: body, else: :lists.droplast(body)

    case inside?(cell, game) and not :lists.member(cell, rest) do
      false -> %{game | over: true}
      true -> eat(%{game | body: [cell | rest], dir: dir}, eats)
    end
  end

  defp eat(%{score: score} = game, true), do: feed(%{game | score: score + 1})
  defp eat(game, false), do: game

  @doc "Milliseconds between steps, shorter with every food eaten."
  @spec interval(map) :: pos_integer
  def interval(%{score: score}), do: max(@start_ms - @speedup_ms * score, @floor_ms)

  @doc "The body as straight runs `{from, to}`, head first; runs share their corner cell."
  @spec runs([cell]) :: [{cell, cell}]
  def runs([cell]), do: [{cell, cell}]
  def runs([a, b | rest]), do: runs(b, delta(a, b), a, rest, [])

  defp runs(last, _d, start, [], acc), do: :lists.reverse([{start, last} | acc])

  defp runs(last, d, start, [cell | rest], acc) do
    case delta(last, cell) do
      ^d -> runs(cell, d, start, rest, acc)
      turn -> runs(cell, turn, last, rest, [{start, last} | acc])
    end
  end

  defp delta({c1, r1}, {c2, r2}), do: {c2 - c1, r2 - r1}

  # Food lands on a random cell, or the next free one after it; a full grid ends the game.
  defp feed(%{cols: cols, rows: rows, body: body, seed: seed} = game) do
    cells = cols * rows

    case length(body) >= cells do
      true ->
        %{game | food: nil, over: true}

      false ->
        seed = rem(seed * 1_103_515_245 + 12_345, 2_147_483_648)
        %{game | seed: seed, food: free(rem(div(seed, 65_536), cells), cols, cells, body)}
    end
  end

  defp free(index, cols, cells, body) do
    cell = {rem(index, cols), div(index, cols)}

    case :lists.member(cell, body) do
      true -> free(rem(index + 1, cells), cols, cells, body)
      false -> cell
    end
  end

  defp inside?({col, row}, %{cols: cols, rows: rows}),
    do: col >= 0 and row >= 0 and col < cols and row < rows
end
