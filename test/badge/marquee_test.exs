defmodule Badge.MarqueeTest do
  use ExUnit.Case, async: true

  alias Badge.Marquee
  alias Badge.Profile

  @effects [:decrypt, :rain, :wipe, :slide]
  @held {:decrypt, :hold, 0, 0}

  defp profile(values), do: Map.merge(Profile.blank(), values)

  defp prep(lines), do: for(line <- lines, do: Marquee.prepare_line(line))

  defp width(:w95fa, text), do: byte_size(text)
  defp width(:dogica, _text), do: 20
  defp width(_font, _text), do: 40

  defp lit?(rows), do: Enum.any?(rows, &(&1 != :binary.copy(" ", byte_size(&1))))

  # Consecutive frames of one glitch, as {first step, last step, {key, effect}, frames}.
  defp runs(views, acc), do: runs(views, 0, nil, acc)

  defp runs([], _step, nil, acc), do: :lists.reverse(acc)
  defp runs([], _step, run, acc), do: :lists.reverse([close(run) | acc])

  defp runs(
         [{_e, {:glitch, key, effect}, k, _s} | rest],
         step,
         {start, _last, {key, effect}, frames},
         acc
       )
       when k == hd(frames) + 1,
       do: runs(rest, step + 1, {start, step, {key, effect}, [k | frames]}, acc)

  defp runs([{_e, {:glitch, key, effect}, k, _s} | rest], step, run, acc) do
    runs(rest, step + 1, {step, step, {key, effect}, [k]}, add(run, acc))
  end

  defp runs([_view | rest], step, run, acc), do: runs(rest, step + 1, nil, add(run, acc))

  defp add(nil, acc), do: acc
  defp add(run, acc), do: [close(run) | acc]

  defp close({start, stop, glitch, frames}), do: {start, stop, glitch, :lists.reverse(frames)}

  describe "lines/1" do
    test "a bare profile shows just the placeholder name" do
      assert Marquee.lines(Profile.blank()) == [{:name, "Nameless"}]
    end

    test "is name, company, hobbies and GitHub, top down, skipping empty ones" do
      full =
        profile(%{name: "Gus", company: "Protolux", github: "@gus", hobbies: "synths, coffee"})

      assert Marquee.lines(full) == [
               {:name, "Gus"},
               {:company, "@Protolux"},
               {:hobbies, "synths / coffee"},
               {:github, "github.com/gus"}
             ]

      assert Marquee.lines(profile(%{name: "Gus", github: "gus"})) ==
               [{:name, "Gus"}, {:github, "github.com/gus"}]
    end

    test "the company gets one @ in front, even if it was typed with one" do
      assert {:company, "@Protolux"} in Marquee.lines(profile(%{company: "Protolux"}))
      assert {:company, "@Protolux"} in Marquee.lines(profile(%{company: "@Protolux"}))
    end

    test "hobbies that are only commas are no line at all" do
      assert Marquee.lines(profile(%{name: "Gus", hobbies: " , "})) == [{:name, "Gus"}]
    end
  end

  describe "prepare/1" do
    test "prepares every line of the profile, in order" do
      full = profile(%{name: "Gus", company: "Protolux", github: "gus"})

      assert for(line <- Marquee.prepare(full), do: line.key) == [:name, :company, :github]
    end
  end

  describe "hobbies/1" do
    test "splits on commas and tidies each one" do
      assert Marquee.hobbies(" synths ,  rock  climbing,,coffee ") ==
               ["synths", "rock climbing", "coffee"]
    end

    test "nothing to split is no hobbies" do
      assert Marquee.hobbies("") == []
      assert Marquee.hobbies(nil) == []
    end
  end

  describe "font/1" do
    test "the name is biggest, a company that fits large, hobbies medium, GitHub plain" do
      assert Marquee.font({:name, "Gus"}) == :big
      assert Marquee.font({:company, "@Protolux"}) == :w95fa
      assert Marquee.font({:hobbies, "synths"}) == :dogica
      assert Marquee.font({:github, "github.com/gus"}) == :default16px
    end

    test "a company too wide for the large font falls back to dogica" do
      assert Marquee.font({:company, "@Goatmire International"}) == :dogica
    end

    test "a name the block font cannot spell falls back to the plain font" do
      assert Marquee.font({:name, "Zoë"}) == :default16px
    end
  end

  describe "rows/2" do
    test "every line is as wide as its font allows across the panel" do
      for line <- [
            {:name, "Gus"},
            {:name, "Bartholomew Cubbins"},
            {:name, "Zoë"},
            {:company, "Protolux"},
            {:company, "Goatmire International Holdings"},
            {:hobbies, "synths"},
            {:github, "github.com/gus"}
          ],
          view <- [@held, {:rain, :in, 3, 17}, {:slide, :out, 2, 40}] do
        for row <- Marquee.rows(Marquee.prepare_line(line), view) do
          assert byte_size(row) == width(Marquee.font(line), elem(line, 1))
        end
      end
    end

    test "the name is three rows of half-block letters" do
      rows = Marquee.rows(Marquee.prepare_line({:name, "Gus"}), @held)

      assert length(rows) == 3
      assert Enum.any?(rows, &(:binary.match(&1, <<0xDB>>) != :nomatch))
    end

    test "lower and upper case draw the same letters" do
      assert Marquee.rows(Marquee.prepare_line({:name, "gus"}), @held) ==
               Marquee.rows(Marquee.prepare_line({:name, "GUS"}), @held)
    end

    test "a line that fits sits centred and still" do
      [row] = Marquee.rows(Marquee.prepare_line({:hobbies, "Protolux"}), @held)

      assert row == "      Protolux      "

      assert Marquee.rows(Marquee.prepare_line({:hobbies, "Protolux"}), {:decrypt, :hold, 0, 7}) ==
               [row]

      refute Marquee.scrolls?({:hobbies, "Protolux"})
    end

    test "a line too long for the panel scrolls a character every two ticks, and wraps round" do
      line = Marquee.prepare_line({:company, "Goatmire International"})
      at = fn scroll -> Marquee.rows(line, {:decrypt, :hold, 0, scroll}) end

      assert line.scrolls
      assert at.(0) == ["Goatmire Internation"]
      assert at.(1) == at.(0)
      assert at.(2) == ["oatmire Internationa"]
      assert at.(44) == ["    Goatmire Interna"]
      assert at.(52) == at.(0)
    end

    test "a long name scrolls a column a frame" do
      line = {:name, "Bartholomew"}
      [first | _] = Marquee.rows(Marquee.prepare_line(line), {:decrypt, :hold, 0, 0})
      [next | _] = Marquee.rows(Marquee.prepare_line(line), {:decrypt, :hold, 0, 1})

      assert Marquee.scrolls?(line)
      assert :binary.part(first, 1, 39) == :binary.part(next, 0, 39)
    end

    test "every effect keeps each line's width on every frame" do
      for line <- [{:name, "Gus"}, {:hobbies, "synths / coffee"}, {:github, "github.com/gus"}],
          effect <- @effects,
          phase <- [:in, :out],
          k <- 0..(Marquee.duration(effect) - 1),
          row <- Marquee.rows(Marquee.prepare_line(line), {effect, phase, k, 0}) do
        assert byte_size(row) == width(Marquee.font(line), elem(line, 1))
      end
    end

    test "a glitch runs its effect on its own line and leaves the others alone" do
      company = Marquee.prepare_line({:company, "@Protolux"})
      hobbies = Marquee.prepare_line({:hobbies, "synths"})
      view = {:decrypt, {:glitch, :company, :slide}, 0, 0}

      assert Marquee.rows(company, view) == Marquee.rows(company, {:slide, :in, 0, 0})
      assert Marquee.rows(hobbies, view) == Marquee.rows(hobbies, @held)
    end

    test "going out runs the effect backwards" do
      line = {:name, "Gus"}

      for effect <- @effects do
        last = Marquee.duration(effect) - 1

        assert Marquee.rows(Marquee.prepare_line(line), {effect, :out, 0, 0}) ==
                 Marquee.rows(Marquee.prepare_line(line), {effect, :in, last, 0})

        assert Marquee.rows(Marquee.prepare_line(line), {effect, :out, last, 0}) ==
                 Marquee.rows(Marquee.prepare_line(line), {effect, :in, 0, 0})
      end
    end

    test "slide and wipe start from an empty panel" do
      for line <- [{:name, "Gus"}, {:company, "Protolux"}] do
        refute lit?(Marquee.rows(Marquee.prepare_line(line), {:slide, :in, 0, 0}))

        refute Enum.any?(
                 Marquee.rows(Marquee.prepare_line(line), {:wipe, :in, 0, 0}),
                 &(:binary.match(&1, "P") != :nomatch)
               )
      end
    end

    test "dogica lines scramble and wipe in plain ASCII, which is all it draws" do
      line = {:company, "Protolux Electronics"}

      for effect <- @effects,
          k <- 0..(Marquee.duration(effect) - 1),
          [row] = Marquee.rows(Marquee.prepare_line(line), {effect, :in, k, 0}),
          <<byte <- row>> do
        assert byte >= 0x20 and byte < 0x7F
      end
    end

    test "a large company never scrolls, keeps its length and scrambles in ASCII" do
      line = Marquee.prepare_line({:company, "@Protolux"})

      refute line.scrolls

      for effect <- @effects,
          phase <- [:in, :out],
          k <- 0..(Marquee.duration(effect) - 1),
          [row] = Marquee.rows(line, {effect, phase, k, 99}) do
        assert byte_size(row) == byte_size("@Protolux")
        for <<byte <- row>>, do: assert(byte >= 0x20 and byte < 0x7F)
      end

      assert Marquee.rows(line, @held) == ["@Protolux"]
    end

    test "decrypt scrambles only where there is text" do
      held = Marquee.rows(Marquee.prepare_line({:name, "Gus"}), @held)
      scrambled = Marquee.rows(Marquee.prepare_line({:name, "Gus"}), {:decrypt, :in, 0, 0})

      for {row, target} <- Enum.zip(scrambled, held),
          {cell, goal} <- Enum.zip(:binary.bin_to_list(row), :binary.bin_to_list(target)),
          goal == ?\s do
        assert cell == ?\s
      end
    end
  end

  describe "view/2" do
    test "starts coming in through decrypt" do
      assert Marquee.view(prep([{:name, "Gus"}]), 0) == {:decrypt, :in, 0, 0}
    end

    test "a still screen keeps one view throughout a hold, so it never redraws" do
      held =
        for step <- 0..109,
            {_e, :hold, _k, _s} = view <- [Marquee.view(prep([{:name, "Gus"}]), step)],
            do: view

      assert length(held) > 50
      assert :lists.usort(held) == [hd(held)]
    end

    test "a scrolling line moves every frame, held or not" do
      lines = [{:name, "Gus"}, {:company, "Goatmire International"}]

      assert {_e, _phase, _k, 60} = Marquee.view(prep(lines), 30)
      assert {_e, _phase, _k, 61} = Marquee.view(prep(lines), 30, 61)
    end

    test "comes in, holds, goes out, and the effects take turns" do
      views = for step <- 0..700, do: Marquee.view(prep([{:name, "Gus"}]), step)

      assert :lists.usort(for {effect, _p, _k, _s} <- views, do: effect) == :lists.sort(@effects)
      assert :lists.usort(for {_e, phase, _k, _s} <- views, do: phase) == [:hold, :in, :out]
    end

    test "a lone name never glitches, so its hold never changes" do
      phases = for step <- 0..2000, do: elem(Marquee.view(prep([{:name, "Gus"}]), step), 1)

      refute Enum.any?(phases, &match?({:glitch, _, _}, &1))
    end

    test "glitches pick only the lower lines that are there, with every effect" do
      lines = prep([{:name, "Gus"}, {:company, "@Protolux"}, {:github, "github.com/gus"}])

      glitches =
        for step <- 0..3000,
            {_e, {:glitch, key, effect}, _k, _s} <- [Marquee.view(lines, step)],
            do: {key, effect}

      assert :lists.usort(for {key, _effect} <- glitches, do: key) == [:company, :github]
      assert :lists.usort(for {_key, effect} <- glitches, do: effect) == :lists.sort(@effects)
    end

    test "one glitch at a time, each run through from its first frame, 1 to 4 seconds apart" do
      lines = prep([{:name, "Gus"}, {:company, "@Protolux"}, {:hobbies, "synths"}])
      views = for step <- 0..3000, do: Marquee.view(lines, step)
      runs = runs(views, [])

      assert length(runs) > 20

      for {start, stop, {_key, effect}, frames} <- runs do
        assert frames == Enum.to_list(0..(Marquee.duration(effect) - 1))
        assert stop - start + 1 == Marquee.duration(effect)
      end

      for [{_s1, stop, _g1, _f1}, {start, _s2, _g2, _f2}] <-
            Enum.chunk_every(runs, 2, 1, :discard),
          Enum.all?(Enum.slice(views, (stop + 1)..(start - 1)//1), &(elem(&1, 1) == :hold)) do
        assert start - stop - 1 >= 5
        assert start - stop - 1 <= 20
      end
    end

    test "glitches keep to holds, which stay still in between" do
      lines = prep([{:name, "Gus"}, {:company, "@Protolux"}])

      for step <- 0..3000 do
        case Marquee.view(lines, step) do
          {_e, {:glitch, _key, _g}, _k, 0} -> :ok
          {_e, :hold, 0, 0} -> :ok
          {_e, phase, _k, 0} -> assert phase in [:in, :out]
        end
      end
    end

    test "each hold plays a different pattern" do
      lines = prep([{:name, "Gus"}, {:company, "@Protolux"}, {:hobbies, "synths"}])

      starts =
        for {start, _stop, _g, _f} <-
              runs(for(step <- 0..3000, do: Marquee.view(lines, step)), []),
            do: start

      gaps = for [a, b] <- Enum.chunk_every(starts, 2, 1, :discard), do: b - a

      assert length(:lists.usort(gaps)) > 3
    end

    test "loops forever" do
      views = for step <- 1..1000, do: Marquee.view(prep([{:name, "Gus"}]), step)

      assert :lists.member({:decrypt, :in, 0, 0}, views)
    end
  end

  describe "logos" do
    # The page puts the picture in; the timeline only asks whether there is one.
    defp with_logo(lines, key) do
      for line <- prep(lines), do: if(line.key == key, do: %{line | logo: :picture}, else: line)
    end

    @lines [{:name, "Gus"}, {:company, "@Nabu Casa"}, {:hobbies, "synths"}]

    defp phases(lines), do: for(step <- 0..3000, do: elem(Marquee.view(lines, step), 1))

    test "a prepared line has no logo until the page gives it one" do
      assert Enum.all?(prep(@lines), &(&1.logo == nil))
      refute Enum.any?(phases(prep(@lines)), &match?({:logo, _, _}, &1))
    end

    test "a line with a logo shows it now and then, and only that line" do
      logos = for {:logo, key, _dir} <- phases(with_logo(@lines, :company)), do: key

      assert length(logos) > 100
      assert :lists.usort(logos) == [:company]
    end

    test "the logo holds 4 s, leaves over 3 frames, then the text decrypts back" do
      lines = with_logo(@lines, :company)
      views = for step <- 0..3000, do: Marquee.view(lines, step)
      phases = for {_e, phase, _k, _s} <- views, do: phase

      starts =
        for {[before, {:logo, :company, :in}], step} <-
              Enum.with_index(Enum.chunk_every(phases, 2, 1, :discard)),
            before != {:logo, :company, :in},
            do: step + 1

      assert length(starts) >= 3

      for start <- starts do
        run = Enum.slice(views, start, 33)

        assert Enum.all?(Enum.take(run, 20), &match?({_e, {:logo, :company, :in}, 0, _s}, &1))

        assert Enum.all?(
                 Enum.slice(run, 20, 3),
                 &match?({_e, {:logo, :company, :out}, 0, _s}, &1)
               )

        assert for({_e, {:glitch, :company, :decrypt}, k, _s} <- Enum.drop(run, 23), do: k) ==
                 Enum.to_list(0..9)
      end
    end

    test "a line with a logo always shows it, and other lines still glitch" do
      phases = phases(with_logo(@lines, :company))
      company = for {:glitch, :company, effect} <- phases, do: effect
      others = for {:glitch, key, _effect} <- phases, key != :company, do: key

      assert :lists.usort(company) == [:decrypt]
      assert others != []
    end

    test "rows during a logo show every line as it holds" do
      [_name, company, _hobbies] = lines = with_logo(@lines, :company)

      for line <- lines do
        assert Marquee.rows(line, {:decrypt, {:logo, company.key, :in}, 0, 0}) ==
                 Marquee.rows(line, @held)
      end
    end
  end
end
