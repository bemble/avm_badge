defmodule Badge.SnakeTest do
  use ExUnit.Case, async: true

  alias Badge.Snake

  defp game(body, dir, food, cols \\ 10, rows \\ 10) do
    %{Snake.new(1, cols, rows) | body: body, dir: dir, next: dir, food: food}
  end

  describe "new/3" do
    test "lays four cells across the middle, heading right, food off the body" do
      game = Snake.new(42, 31, 21)

      assert game.body == [{15, 10}, {14, 10}, {13, 10}, {12, 10}]
      assert game.dir == {1, 0}
      assert {col, row} = game.food
      assert col in 0..30 and row in 0..20
      refute game.food in game.body
    end

    test "the same seed places the same food" do
      assert Snake.new(7, 31, 21).food == Snake.new(7, 31, 21).food
    end
  end

  describe "step/1" do
    test "moves the head and drops the tail" do
      next = Snake.step(game([{5, 5}, {4, 5}, {3, 5}], {1, 0}, {0, 0}))

      assert next.body == [{6, 5}, {5, 5}, {4, 5}]
      refute next.over
    end

    test "eating grows by one, scores and places new food on a free cell" do
      next = Snake.step(game([{5, 5}, {4, 5}, {3, 5}], {1, 0}, {6, 5}))

      assert next.body == [{6, 5}, {5, 5}, {4, 5}, {3, 5}]
      assert next.score == 1
      refute next.food in next.body
    end

    test "a wall ends the game" do
      assert Snake.step(game([{9, 5}, {8, 5}], {1, 0}, {0, 0})).over
      assert Snake.step(game([{0, 5}, {1, 5}], {-1, 0}, {9, 9})).over
      assert Snake.step(game([{5, 0}, {5, 1}], {0, -1}, {9, 9})).over
      assert Snake.step(game([{5, 9}, {5, 8}], {0, 1}, {0, 0})).over
    end

    test "running into the body ends the game" do
      body = [{5, 5}, {5, 6}, {6, 6}, {6, 5}, {6, 4}]

      assert Snake.step(game(body, {0, -1}, {0, 0}) |> Snake.turn({1, 0})).over
    end

    test "the cell the tail is leaving is free to enter" do
      body = [{5, 5}, {5, 6}, {6, 6}, {6, 5}]

      refute Snake.step(game(body, {0, -1}, {0, 0}) |> Snake.turn({1, 0})).over
    end
  end

  describe "dir/1" do
    test "names each arrow's step" do
      assert Snake.dir(:up) == {0, -1}
      assert Snake.dir(:down) == {0, 1}
      assert Snake.dir(:left) == {-1, 0}
      assert Snake.dir(:right) == {1, 0}
    end
  end

  describe "turn/2" do
    test "a reversal is ignored" do
      assert Snake.turn(game([{5, 5}, {4, 5}], {1, 0}, {0, 0}), {-1, 0}).next == {1, 0}
    end

    test "only the first turn of a step is kept" do
      turned = game([{5, 5}, {4, 5}], {1, 0}, {0, 0}) |> Snake.turn({0, -1}) |> Snake.turn({0, 1})

      assert turned.next == {0, -1}
      assert Snake.step(turned).body == [{5, 4}, {5, 5}]
      assert Snake.step(turned).dir == {0, -1}
    end

    test "two quick turns cannot fold the snake back on itself" do
      turned =
        game([{5, 5}, {4, 5}, {3, 5}], {1, 0}, {0, 0})
        |> Snake.turn({0, -1})
        |> Snake.turn({-1, 0})

      refute Snake.step(turned).over
    end
  end

  describe "food placement" do
    test "lands on the one free cell whatever the seed" do
      for seed <- 1..20 do
        game = %{
          Snake.new(seed, 2, 2)
          | body: [{1, 0}, {0, 0}],
            dir: {0, 1},
            next: {0, 1},
            food: {1, 1},
            over: false
        }

        assert Snake.step(game).food == {0, 1}
      end
    end

    test "filling the grid ends the game" do
      game = %{
        Snake.new(1, 3, 1)
        | body: [{1, 0}, {0, 0}],
          dir: {1, 0},
          food: {2, 0},
          over: false
      }

      assert %{over: true, score: 1, food: nil} = Snake.step(game)
    end
  end

  describe "interval/1" do
    test "starts at 200 ms and quickens by 4 ms a food down to 100 ms" do
      assert Snake.interval(%{score: 0}) == 200
      assert Snake.interval(%{score: 5}) == 180
      assert Snake.interval(%{score: 25}) == 100
      assert Snake.interval(%{score: 90}) == 100
    end
  end

  describe "runs/1" do
    test "a straight snake is one run" do
      assert Snake.runs([{5, 5}, {4, 5}, {3, 5}]) == [{{5, 5}, {3, 5}}]
    end

    test "a lone head is a run of one cell" do
      assert Snake.runs([{5, 5}]) == [{{5, 5}, {5, 5}}]
    end

    test "every turn starts a new run at the corner" do
      body = [{5, 3}, {5, 4}, {5, 5}, {4, 5}, {3, 5}, {3, 6}]

      assert Snake.runs(body) == [{{5, 3}, {5, 5}}, {{5, 5}, {3, 5}}, {{3, 5}, {3, 6}}]
    end

    test "a zig-zag of single steps is one run per turn plus one" do
      body = [{0, 0}, {1, 0}, {1, 1}, {2, 1}, {2, 2}]

      assert length(Snake.runs(body)) == 4
    end
  end
end
