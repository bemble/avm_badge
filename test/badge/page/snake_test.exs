defmodule Badge.Page.SnakeTest do
  use ExUnit.Case, async: true

  alias Badge.Page.Snake, as: Page
  alias Badge.Skin

  defp key(state, event) do
    {:ok, next} = Page.handle_key(event, state)
    next
  end

  defp enter(state), do: key(state, {:edit, :newline})

  # A game past its first deal, at time 10_000.
  defp playing do
    state = %{Page.init() | best: 0} |> enter()
    state = Page.advance(state, 0)

    %{state | due: 10_000}
  end

  defp next_dir(event), do: playing() |> key(event) |> Map.get(:game) |> Map.get(:next)

  defp inside?(items) do
    Enum.all?(items, fn
      {:rect, x, y, w, h, _colour} ->
        x >= 0 and y >= 0 and x + w <= 320 and y + h <= 240

      {:text, x, y, font, _fg, _bg, text} ->
        x >= 0 and y >= 0 and x + width(font) * byte_size(text) <= 320 and y + 16 <= 240
    end)
  end

  defp width(:dogica), do: 16
  defp width(:default16px), do: 8

  defp skinned(skin, fun) do
    old = Skin.current()
    Skin.activate(skin)

    try do
      fun.()
    after
      Skin.activate(old)
    end
  end

  defp luminance(colour) do
    div(colour, 0x10000) + rem(div(colour, 0x100), 0x100) + rem(colour, 0x100)
  end

  describe "identity" do
    test "owns the whole panel" do
      assert Page.title() == "Snake"
      refute Page.chrome?(Page.init())
    end

    test "is on the home grid" do
      assert Badge.Page.Snake in Badge.Pages.all()
    end
  end

  describe "the title screen" do
    test "Enter starts a game" do
      assert %{screen: :play, game: nil} = Page.init() |> enter()
    end

    test "Escape and shape keys are left to the router" do
      assert Page.handle_key({:nav, :home}, Page.init()) == :ignore
      assert Page.handle_key({:nav, :square}, Page.init()) == :ignore
    end

    test "shows the best score and the hint" do
      state = %{Page.init() | best: 12}
      texts = for {:text, _x, _y, _font, _fg, _bg, text} <- Page.render(state), do: text

      assert "SNAKE" in texts
      assert "Best 0012" in texts
      assert "Enter to play" in texts
    end
  end

  describe "a game" do
    test "the first tick deals the game and waits before moving" do
      state = Page.init() |> enter() |> Page.advance(500)

      assert %{body: [_ | _]} = state.game
      assert Page.advance(state, 600) == state
    end

    test "steps once the interval has passed, and not before" do
      state = playing()
      head = hd(state.game.body)

      assert Page.advance(state, 9_999) == state

      moved = Page.advance(state, 10_000)
      assert hd(moved.game.body) == {elem(head, 0) + 1, elem(head, 1)}
      assert moved.due == 10_200
    end

    test "arrows turn the snake" do
      assert playing() |> key({:move, :up}) |> Map.get(:game) |> Map.get(:next) == {0, -1}
    end

    test "Z, Ctrl, SP and Alt steer like the arrows" do
      assert next_dir({:char, ?z}) == {0, -1}
      assert next_dir({:char, ?Z}) == {0, -1}
      assert next_dir({:mod, :solder}) == {0, 1}
      assert next_dir({:move, :down}) == {0, 1}
      assert next_dir({:mod, :ctrl}) == next_dir({:move, :left})
      assert next_dir({:mod, :alt}) == next_dir({:move, :right})
    end

    test "other keys and the title screen ignore them" do
      assert Page.handle_key({:mod, :ctrl}, Page.init()) == :ignore
      assert Page.handle_key({:char, ?q}, playing()) == :ignore
      assert Page.handle_key({:mod, :unknown}, playing()) == :ignore
    end

    test "Escape backs out to the title screen" do
      assert %{screen: :title} = key(playing(), {:nav, :home})
    end

    test "hitting the wall ends it and keeps the record" do
      state = %{playing() | best: 3}
      state = %{state | game: %{state.game | body: [{30, 5}, {29, 5}], score: 5}}

      over = Page.advance(state, 10_000)

      assert over.screen == :over
      assert over.best == 5
      assert %{screen: :play, game: nil} = enter(over)
      assert %{screen: :title} = key(over, {:nav, :home})
    end

    test "a lower score keeps the old record" do
      state = %{playing() | best: 9}
      state = %{state | game: %{state.game | body: [{30, 5}, {29, 5}], score: 5}}

      assert Page.advance(state, 10_000).best == 9
    end
  end

  describe "render/1" do
    test "a snake with N turns is N + 1 rects, drawn inside the panel" do
      state = playing()
      body = [{5, 3}, {5, 4}, {5, 5}, {4, 5}, {3, 5}, {3, 6}]
      straight = Page.render(%{state | game: %{state.game | body: [{5, 3}, {5, 4}, {5, 5}]}})
      turned = Page.render(%{state | game: %{state.game | body: body}})

      assert length(turned) == length(straight) + 2
      assert inside?(turned)
    end

    test "every screen ends with a full-panel background" do
      over = %{playing() | screen: :over}

      for state <- [Page.init(), playing(), over] do
        items = Page.render(state)

        assert {:rect, 0, 0, 320, 240, _bg} = List.last(items)
        assert inside?(items)
      end
    end

    test "the background is dark and the text readable in every skin" do
      for skin <- Badge.Skin.all() do
        skinned(skin, fn ->
          for state <- [Page.init(), playing(), %{playing() | screen: :over}] do
            items = Page.render(state)
            {:rect, 0, 0, 320, 240, bg} = List.last(items)

            assert luminance(bg) < 200, inspect(skin)

            for {:text, _x, _y, _font, fg, tbg, _text} <- items do
              assert tbg == bg
              assert luminance(fg) >= 288, inspect(skin)
            end
          end
        end)
      end
    end

    test "the snake takes the skin's accent and head its select colour" do
      skinned(Badge.Skin.Dark, fn ->
        colours = for {:rect, _, _, _, _, colour} <- Page.render(playing()), do: colour

        assert Badge.Theme.accent() in colours
        assert Badge.Theme.select() in colours
      end)
    end
  end

  describe "LED cues" do
    test "eating flashes green" do
      state = playing()
      ate = %{state | game: %{state.game | score: state.game.score + 1}}

      assert {120, _ms} = Page.cue(state, ate)
    end

    test "losing flashes red for longer" do
      state = playing()
      {120, eat} = Page.cue(state, %{state | game: %{state.game | score: 1}})

      assert {0, lose} = Page.cue(state, %{state | screen: :over})
      assert lose > eat
    end

    test "a plain step or a key press flashes nothing" do
      state = playing()

      assert Page.cue(state, state) == nil
      assert Page.cue(Page.init(), enter(Page.init())) == nil
    end
  end

  describe "best score" do
    test "round-trips through its NVS value" do
      assert Page.encode(300) == <<1, 44>>
      assert Page.decode(<<1, 44>>) == 300
    end

    test "an older two-count value gives its keys score" do
      assert Page.decode(<<0, 12, 1, 44>>) == 12
    end

    test "an absent or damaged value counts as none" do
      assert Page.decode(nil) == 0
      assert Page.decode("123") == 0
    end
  end
end
