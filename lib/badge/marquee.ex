defmodule Badge.Marquee do
  @moduledoc """
  Text-mode animation of the profile for the Name page's live screen.

  Four lines, top down: the name in a 3x5 block font made of half-block
  characters, the company in w95fa when it fits and dogica when not, the
  hobbies in dogica, and the GitHub handle in the plain 8x16 font. A line too long for the panel scrolls by; the rest
  sit centred. Every so often the whole screen leaves and comes back
  through an effect, and the effects take turns. In between, one of the
  lower lines at random replays a random effect every few seconds, or, when
  it has a logo, shows the logo for a few seconds instead.

  A line is a list of rows, each a binary exactly as wide as its font allows
  across the panel, so a frame is one text item per row. Frames are meant to
  be a few per second: everything here reads well at five.

  Pure: the page prepares the lines once with `prepare/1`, turns elapsed time
  into a step, and asks `view/2` and `rows/2` what to show. Nothing costly
  runs per frame beyond cutting the scroll window and the effect.
  """

  alias Badge.Font
  alias Badge.Profile
  alias Badge.Text

  @panel_cols 40
  @dogica_cols 20

  # The Name page's big-name font, and the width it may take with a margin each side.
  @large :w95fa
  @large_width 320 - 2 * 16

  @effects {:decrypt, :rain, :wipe, :slide}
  @hold 100

  # While the screen holds, one of the lower lines replays an effect every 1 to 4 seconds.
  @lower [:company, :hobbies, :github]
  @glitch_gap 5
  @glitch_spread 16

  # Three glitches in four go to a line with a logo: in, out, then its text decrypts back.
  @logo_in 20
  @logo_out 3
  @logo_back :decrypt

  # Blank columns, or characters, between the end of a scrolling line and its start.
  @big_gap 6
  @text_gap 4

  # Rain falls down the whole screen, so each line's rows sit at their place in it.
  @rain_rows %{name: 0, company: 4, hobbies: 6, github: 10}
  @rain_depth 11

  # Frames each effect takes, in @effects order; the whole cycle's length follows.
  @durations {10, @rain_depth + 8, div(@panel_cols, 4) + 3, 8}
  @period 2 * Enum.sum(Tuple.to_list(@durations)) + tuple_size(@effects) * @hold

  # Lines slide in from alternate sides: true is from the left.
  @from_left %{name: true, company: false, hobbies: true, github: false}

  @font [
    {?A, ".#. #.# ### #.# #.#"},
    {?B, "##. #.# ##. #.# ##."},
    {?C, ".## #.. #.. #.. .##"},
    {?D, "##. #.# #.# #.# ##."},
    {?E, "### #.. ##. #.. ###"},
    {?F, "### #.. ##. #.. #.."},
    {?G, ".## #.. #.# #.# .##"},
    {?H, "#.# #.# ### #.# #.#"},
    {?I, "### .#. .#. .#. ###"},
    {?J, "..# ..# ..# #.# .#."},
    {?K, "#.# #.# ##. #.# #.#"},
    {?L, "#.. #.. #.. #.. ###"},
    {?M, "#.# ### ### #.# #.#"},
    {?N, "##. #.# #.# #.# #.#"},
    {?O, ".#. #.# #.# #.# .#."},
    {?P, "##. #.# ##. #.. #.."},
    {?Q, ".#. #.# #.# ##. .##"},
    {?R, "##. #.# ##. #.# #.#"},
    {?S, ".## #.. .#. ..# ##."},
    {?T, "### .#. .#. .#. .#."},
    {?U, "#.# #.# #.# #.# ###"},
    {?V, "#.# #.# #.# #.# .#."},
    {?W, "#.# #.# ### ### #.#"},
    {?X, "#.# #.# .#. #.# #.#"},
    {?Y, "#.# #.# .#. .#. .#."},
    {?Z, "### ..# .#. #.. ###"},
    {?0, "### #.# #.# #.# ###"},
    {?1, ".#. ##. .#. .#. ###"},
    {?2, "##. ..# .#. #.. ###"},
    {?3, "##. ..# .#. ..# ##."},
    {?4, "#.# #.# ### ..# ..#"},
    {?5, "### #.. ##. ..# ##."},
    {?6, ".## #.. ### #.# ###"},
    {?7, "### ..# .#. .#. .#."},
    {?8, "### #.# ### #.# ###"},
    {?9, "### #.# ### ..# ##."},
    {?\s, "... ... ... ... ..."},
    {?-, "... ... ### ... ..."},
    {?., "... ... ... ... .#."},
    {?_, "... ... ... ... ###"},
    {?@, "### #.# ### #.. .##"},
    {?/, "..# ..# .#. #.. #.."},
    {?&, ".#. #.# .#. #.# .##"},
    {?', ".#. .#. ... ... ..."},
    {?!, ".#. .#. .#. ... .#."},
    {??, "##. ..# .#. ... .#."},
    {?,, "... ... ... .#. #.."},
    {?:, "... .#. ... .#. ..."},
    {?+, "... .#. ### .#. ..."},
    {?#, "#.# ### #.# ### #.#"},
    {?(, ".#. #.. #.. #.. .#."},
    {?), ".#. ..# ..# ..# .#."}
  ]

  # Pixel rows pair up into half blocks: both lit, top only, bottom only.
  half = fn
    {?#, ?#} -> 0xDB
    {?#, ?.} -> 0xDF
    {?., ?#} -> 0xDC
    {?., ?.} -> ?\s
  end

  for {char, art} <- @font do
    [p0, p1, p2, p3, p4] = for row <- String.split(art), do: String.to_charlist(row)

    rows =
      for {top, bottom} <- [{p0, p1}, {p2, p3}, {p4, ~c"..."}],
          do: :erlang.list_to_binary(for pair <- Enum.zip(top, bottom), do: half.(pair))

    defp glyph(unquote(char)), do: unquote(Macro.escape(List.to_tuple(rows)))
  end

  defp glyph(char) when char >= ?a and char <= ?z, do: glyph(char - 32)
  defp glyph(_char), do: :none

  # Scrambled cells for the block and 8x16 lines, which draw code page 437.
  @noise <<0xB0, 0xB1, 0xB2, 0xDB, 0xDC, 0xDF, 0xB3, 0xC4, 0xC5, 0xCE, 0xBA, 0xCD, 0xF9, 0xFE>> <>
           "01/\\<>*+#%"

  # dogica has ASCII only, so its lines scramble and wipe in plain characters.
  @ascii_noise "01/\\<>*+#%=?$&"

  @doc """
  The lines to show for a profile, as `{key, text}`, top down.

  The name is always there; company, hobbies and GitHub only when filled in.
  The company gets an `@` in front, and hobbies are joined with slashes.
  """
  @spec lines(map) :: [{atom, binary}]
  def lines(profile) do
    [{:name, Profile.display_name(profile)}] ++
      company(handle(Map.get(profile, :company, ""))) ++
      line(:hobbies, join(hobbies(Map.get(profile, :hobbies, "")), " / ")) ++
      github(handle(Map.get(profile, :github, "")))
  end

  defp line(key, text) do
    case Profile.present?(text) do
      true -> [{key, text}]
      false -> []
    end
  end

  defp company(""), do: []
  defp company(name), do: [{:company, "@" <> name}]

  defp github(""), do: []
  defp github(handle), do: [{:github, "github.com/" <> handle}]

  defp handle(nil), do: ""
  defp handle(<<"@", rest::binary>>), do: rest
  defp handle(value), do: value

  @doc "The comma-separated items in `value`, trimmed, with empty ones dropped."
  @spec hobbies(binary | nil) :: [binary]
  def hobbies(nil), do: []
  def hobbies(value), do: :lists.filter(&Profile.present?/1, split(value, <<>>, []))

  defp split(<<>>, item, acc), do: :lists.reverse([tidy(item) | acc])
  defp split(<<?,, rest::binary>>, item, acc), do: split(rest, <<>>, [tidy(item) | acc])
  defp split(<<char, rest::binary>>, item, acc), do: split(rest, <<item::binary, char>>, acc)

  defp tidy(item), do: join(Text.words(item), " ")

  defp join([], _separator), do: <<>>

  defp join([word | rest], separator) do
    :lists.foldl(fn next, acc -> acc <> separator <> next end, word, rest)
  end

  @doc """
  The font a line draws in: `:big` for block letters, drawn as rows of the
  8x16 font, or the font its single row takes. A name the block font cannot
  spell falls back to the 8x16 font, and a company too wide for w95fa to
  dogica, where it scrolls.
  """
  @spec font({atom, binary}) :: :big | :w95fa | :dogica | :default16px
  def font({:name, text}) do
    case drawable?(text) do
      true -> :big
      false -> :default16px
    end
  end

  def font({:github, _text}), do: :default16px

  def font({:company, text}) do
    case Font.fits?(@large, text, @large_width) do
      true -> @large
      false -> :dogica
    end
  end

  def font({_key, _text}), do: :dogica

  @doc "Whether a line is too long to sit still, and so scrolls."
  @spec scrolls?({atom, binary}) :: boolean
  def scrolls?(line), do: prepare_line(line).scrolls

  @doc "Every line of a profile, ready to draw frame after frame."
  @spec prepare(map) :: [map]
  def prepare(profile), do: for(line <- lines(profile), do: prepare_line(line))

  @doc "One line's rows, font and effect settings, worked out once."
  @spec prepare_line({atom, binary}) :: map
  def prepare_line({key, _text} = line) do
    font = font(line)
    source = source_rows(line, font)
    columns = columns(font, source)

    %{
      key: key,
      font: font,
      source: source,
      columns: columns,
      gap: gap(font),
      scrolls: byte_size(hd(source)) > columns,
      pixels: pixels(font, source),
      pace: pace(font),
      base: Map.get(@rain_rows, key, 0),
      noise: noise(font),
      edge: edge(font),
      from_left: Map.get(@from_left, key, true),
      logo: nil
    }
  end

  @doc """
  What to show `step` frames in, as `{effect, phase, frame, scroll}`.

  Phase is `:in`, `:hold` or `:out`, or `{:glitch, key, effect}` while one
  line replays an effect during a hold, with the frame counting through it,
  or `{:logo, key, :in | :out}` while a line with a `logo` shows it instead,
  reporting frame 0.
  A held frame reports frame 0, and scroll is 0 unless some line scrolls,
  so a still screen only changes its view for a glitch.

  Scroll counts half frames, `ticks`: the block name moves a column each,
  the other lines a character every two. It defaults to two per frame.
  """
  @spec view([map], non_neg_integer, non_neg_integer) ::
          {atom, atom, non_neg_integer, non_neg_integer}
  def view(lines, step, ticks \\ nil) do
    scroll =
      case :lists.any(fn line -> line.scrolls end, lines) do
        true when ticks == nil -> 2 * step
        true -> ticks
        false -> 0
      end

    period = period()

    case phase(0, rem(step, period)) do
      {effect, :hold, turn, held} ->
        seed = rem(div(step, period) * tuple_size(@effects) + turn, 101)
        {phase, k} = glitch(lower(lines), logos(lines), seed, held)

        {effect, phase, k, scroll}

      {effect, phase, k} ->
        {effect, phase, k, scroll}
    end
  end

  defp lower(lines), do: for(%{key: key} <- lines, :lists.member(key, @lower), do: key)

  defp logos(lines), do: for(%{key: key, logo: logo} <- lines, logo != nil, do: key)

  defp glitch([], _logos, _seed, _held), do: {:hold, 0}
  defp glitch(keys, logos, seed, held), do: glitch(keys, logos, seed, held, 0, 0)

  # Glitch n starts a random gap after the last one ends; one that would outlast the hold is skipped.
  defp glitch(keys, logos, seed, held, n, free) do
    start = free + @glitch_gap + rem(hash(seed, n, 3), @glitch_spread)
    key = glitch_key(keys, logos, seed, n)
    logo = :lists.member(key, logos)

    effect =
      case logo do
        true -> :logo
        false -> elem(@effects, rem(hash(seed, n, 5), tuple_size(@effects)))
      end

    finish = start + glitch_length(effect)

    cond do
      held < start or finish > @hold -> {:hold, 0}
      held < finish -> glitch_phase(key, effect, held - start)
      true -> glitch(keys, logos, seed, held, n + 1, finish)
    end
  end

  defp glitch_key(keys, [], seed, n), do: pick(keys, hash(seed, n, 7))

  defp glitch_key(keys, logos, seed, n) do
    case rem(hash(seed, n, 11), 4) do
      0 -> pick(keys, hash(seed, n, 17))
      _logo -> pick(weighted(logos), hash(seed, n, 7))
    end
  end

  # The company's logo comes up twice as often as a hobby's.
  defp weighted(logos) do
    case :lists.member(:company, logos) do
      true -> [:company | logos]
      false -> logos
    end
  end

  defp glitch_length(:logo), do: @logo_in + @logo_out + duration(@logo_back)
  defp glitch_length(effect), do: duration(effect)

  defp glitch_phase(key, :logo, k) when k < @logo_in, do: {{:logo, key, :in}, 0}
  defp glitch_phase(key, :logo, k) when k < @logo_in + @logo_out, do: {{:logo, key, :out}, 0}
  defp glitch_phase(key, :logo, k), do: {{:glitch, key, @logo_back}, k - @logo_in - @logo_out}
  defp glitch_phase(key, effect, k), do: {{:glitch, key, effect}, k}

  defp pick(keys, hash), do: :lists.nth(rem(hash, length(keys)) + 1, keys)

  defp period, do: @period

  defp turn_length(turn), do: 2 * duration(elem(@effects, turn)) + @hold

  defp phase(turn, step) do
    effect = elem(@effects, turn)
    fade = duration(effect)

    cond do
      step < fade -> {effect, :in, step}
      step < fade + @hold -> {effect, :hold, turn, step - fade}
      step < 2 * fade + @hold -> {effect, :out, step - fade - @hold}
      true -> phase(turn + 1, step - turn_length(turn))
    end
  end

  @doc "How many frames an effect takes to bring the screen in, and again to take it out."
  @spec duration(atom) :: pos_integer
  def duration(:decrypt), do: elem(@durations, 0)
  def duration(:rain), do: elem(@durations, 1)
  def duration(:wipe), do: elem(@durations, 2)
  def duration(:slide), do: elem(@durations, 3)

  @doc "A prepared line's rows as they look in a view: scrolled into place, then through the effect."
  @spec rows(map, tuple) :: [binary]
  def rows(line, {effect, phase, k, scroll}) do
    placed =
      for row <- line.source, do: place(row, line.columns, line.gap, div(scroll, line.pace))

    style = line

    case phase do
      :hold -> placed
      :in -> draw(effect, placed, k, style)
      :out -> draw(effect, placed, duration(effect) - 1 - k, style)
      {:glitch, key, glitch} when key == line.key -> draw(glitch, placed, k, style)
      {:glitch, _key, _glitch} -> placed
      {:logo, _key, _direction} -> placed
    end
  end

  # A w95fa line is proportional and only drawn when it fits, so it is as wide as its text.
  defp columns(:w95fa, [row]), do: byte_size(row)
  defp columns(:dogica, _source), do: @dogica_cols
  defp columns(_font, _source), do: @panel_cols

  # Measured once: reading the font's width table is costly on the badge.
  defp pixels(@large, [row]), do: Font.width(@large, row)
  defp pixels(_font, _source), do: nil

  # Half frames per column or character a scrolling line moves.
  defp pace(:big), do: 1
  defp pace(_font), do: 2

  defp gap(:big), do: @big_gap
  defp gap(_font), do: @text_gap

  defp noise(font) when font == :dogica or font == @large, do: @ascii_noise
  defp noise(_font), do: @noise

  defp edge(font) when font == :dogica or font == @large, do: "#=-"
  defp edge(_font), do: <<0xB2, 0xB1, 0xB0>>

  # The whole line before it is cut to the panel: one row, or three of block letters.
  defp source_rows({_key, text}, :big), do: for(row <- [0, 1, 2], do: big_row(text, row, <<>>))
  defp source_rows({_key, text}, :default16px), do: [Text.cp437(text)]
  defp source_rows({_key, text}, _font), do: [text]

  # A row that fits is centred; a longer one loops past, a column or character a frame.
  defp place(row, columns, _gap, _scroll) when byte_size(row) <= columns, do: centre(row, columns)

  defp place(row, columns, gap, scroll) do
    loop = row <> :binary.copy(" ", gap)

    :binary.part(loop <> loop, rem(scroll, byte_size(loop)), columns)
  end

  defp centre(row, columns) do
    left = div(columns - byte_size(row), 2)

    :binary.copy(" ", left) <> row <> :binary.copy(" ", columns - byte_size(row) - left)
  end

  defp drawable?(<<>>), do: true
  defp drawable?(<<char, rest::binary>>), do: glyph(char) != :none and drawable?(rest)

  defp big_row(<<>>, _row, acc), do: acc
  defp big_row(<<char>>, row, acc), do: <<acc::binary, elem(glyph(char), row)::binary>>

  defp big_row(<<char, rest::binary>>, row, acc) do
    big_row(rest, row, <<acc::binary, elem(glyph(char), row)::binary, " ">>)
  end

  # Each letter resolves out of noise at its own frame; the rest keeps changing.
  defp draw(:decrypt, rows, k, style) do
    noise = style.noise

    cells(rows, style, fn
      ?\s, _r, _c -> ?\s
      target, r, c -> if k > rem(hash(r, c, 0), 9), do: target, else: scramble(noise, r, c, k)
    end)
  end

  # Columns start at different times; each fills downwards behind a falling glyph.
  defp draw(:rain, rows, k, style) do
    noise = style.noise

    cells(rows, style, fn target, r, c ->
      head = k - rem(hash(0, c, 1), 8)

      cond do
        head > r -> target
        head == r -> scramble(noise, r, c, k)
        true -> ?\s
      end
    end)
  end

  # A shaded bar sweeps left to right, leaving the text behind it.
  defp draw(:wipe, rows, k, style) do
    shades = style.edge
    edge = div(4 * k * byte_size(hd(rows)), @panel_cols) - 2

    cells(rows, style, fn target, _r, c ->
      cond do
        c < edge -> target
        c <= edge + 2 -> :binary.at(shades, c - edge)
        true -> ?\s
      end
    end)
  end

  # Lines glide in, alternately from the left and the right.
  defp draw(:slide, rows, k, style) do
    for row <- rows do
      shift(row, div(5 * (duration(:slide) - k) * byte_size(row), @panel_cols), style.from_left)
    end
  end

  defp shift(row, offset, _right) when offset >= byte_size(row),
    do: :binary.copy(" ", byte_size(row))

  defp shift(row, offset, true) do
    :binary.copy(" ", offset) <> :binary.part(row, 0, byte_size(row) - offset)
  end

  defp shift(row, offset, false) do
    :binary.part(row, offset, byte_size(row) - offset) <> :binary.copy(" ", offset)
  end

  defp numbered([], _r, acc), do: :lists.reverse(acc)
  defp numbered([row | rest], r, acc), do: numbered(rest, r + 1, [{row, r} | acc])

  defp cells(rows, style, fun) do
    for {row, r} <- numbered(rows, style.base, []), do: row_cells(row, r, 0, fun, [])
  end

  # Built as a list and packed once; appending to a binary copies it every time.
  defp row_cells(<<>>, _r, _c, _fun, acc), do: :erlang.list_to_binary(:lists.reverse(acc))

  defp row_cells(<<target, rest::binary>>, r, c, fun, acc) do
    row_cells(rest, r, c + 1, fun, [fun.(target, r, c) | acc])
  end

  defp scramble(noise, r, c, k), do: :binary.at(noise, rem(hash(r, c, k), byte_size(noise)))

  # Small enough that nothing here is boxed on a 32-bit VM.
  defp hash(r, c, salt) do
    x = r * 13 + c * 29 + salt * 7 + 11

    rem(x * x + 3 * x, 1009)
  end
end
