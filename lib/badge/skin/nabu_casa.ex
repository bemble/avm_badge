defmodule Badge.Skin.NabuCasa do
  @moduledoc """
  Nabu Casa's brand colours on the Neon Dusk layout: a slate blue-grey
  primary, a warm yellow sun and cursor, and a calmer panel with only the
  pulsing horizon and the chaser.
  """

  @behaviour Badge.Skin

  alias Badge.Icons
  alias Badge.Theme

  @bar 0x0A0D12
  @surface 0x000000
  @title 0xF2F5F9
  @caption 0xA8B7CD
  @divider 0x2A3240
  @yellow 0xFFDE77

  @horizon [0xFFDE77, 0xA8B7CD, 0x5E7BA6]
  @segments 10
  @segment_w div(Theme.width(), @segments)

  # Colours are 0xRRGGBB; mix/3 blends a toward b by num/den per channel.
  mix = fn a, b, num, den ->
    channel = fn shift ->
      ca = rem(div(a, shift), 0x100)
      cb = rem(div(b, shift), 0x100)
      ca + div((cb - ca) * num, den)
    end

    channel.(0x10000) * 0x10000 + channel.(0x100) * 0x100 + channel.(1)
  end

  [yellow, primary, blue] = @horizon
  half = div(@segments - 1, 2)

  @gradient (for i <- 0..(@segments - 1) do
               case i <= half do
                 true -> mix.(yellow, primary, i, half)
                 false -> mix.(primary, blue, i - half, @segments - 1 - half)
               end
             end)

  @glow for colour <- @gradient, do: mix.(@surface, colour, 3, 10)

  # The horizon and its glow row as decor lines, drawn over the chrome's own and pulsing together.
  @horizon_glow for colour <- @horizon, do: mix.(@surface, colour, 3, 10)
  @pulse_ms 2400
  @pulse_floor 35

  # A striped sun: {dx, dy, w, h} bands, widest at the horizon.
  @sun_x 6
  @sun_y 5
  @sun [
    {4, 0, 4, 1},
    {2, 1, 8, 1},
    {1, 2, 10, 1},
    {0, 3, 12, 2},
    {0, 6, 12, 2},
    {0, 9, 12, 1},
    {0, 11, 12, 1}
  ]

  @status_y 3
  @status_margin 6
  @status_gap 6
  @status_w elem(Icons.size(:battery_100), 0)
  @battery_x Theme.width() - @status_margin - @status_w
  @wifi_x @battery_x - @status_gap - @status_w
  @title_x @sun_x + 12 + 6
  @char_w 8

  @horizon_items (for {colour, glow, i} <-
                        :lists.zip3(@gradient, @glow, Enum.to_list(0..(@segments - 1))) do
                    x = i * @segment_w
                    y = Theme.bar_h()

                    [{:rect, x, y, @segment_w, 2, colour}, {:rect, x, y + 2, @segment_w, 1, glow}]
                  end)
                 |> List.flatten()

  @sun_items for {dx, dy, w, h} <- @sun, do: {:rect, @sun_x + dx, @sun_y + dy, w, h, @yellow}

  @impl true
  def name, do: "NabuCasa"

  @impl true
  def bg, do: @surface
  @impl true
  def fg, do: 0xDCE3EC
  @impl true
  def muted, do: @caption
  @impl true
  def dim, do: 0x5F6B7D
  @impl true
  def accent, do: 0xC4D0E0
  @impl true
  def ok, do: 0x6CD49A
  @impl true
  def warn, do: 0xFFB454
  @impl true
  def alert, do: 0xF2596C
  @impl true
  def select, do: @yellow
  @impl true
  def glyph, do: 0xFFFFFF

  @impl true
  def chrome(title, status) do
    [
      Icons.item(status.battery, @battery_x, @status_y, glyph(), @bar),
      Icons.item(status.wifi, @wifi_x, @status_y, glyph(), @bar),
      clock_item(status.clock),
      {:text, @title_x, @status_y, :pixel_operator, @title, @bar, title}
    ] ++
      @sun_items ++
      @horizon_items ++
      [
        {:rect, 0, 0, Theme.width(), Theme.bar_h(), @bar},
        {:rect, 0, 0, Theme.width(), Theme.height(), @surface}
      ]
  end

  # A pulsing horizon and a chaser round the panel.
  @impl true
  def decor do
    [
      {:line, 0, Theme.bar_h(), Theme.width(), 2, @horizon, :pulse, @pulse_ms, @pulse_floor},
      {:line, 0, Theme.bar_h() + 2, Theme.width(), 1, @horizon_glow, :pulse, @pulse_ms,
       @pulse_floor},
      {:chaser, 3, 420, 36, 64, [0xFFF6D6, 0xFFDE77, 0xA8B7CD]}
    ]
  end

  @impl true
  def rule(x, y, w), do: [{:rect, x, y, w, 1, @divider}]

  defp clock_item(clock) do
    x = div(Theme.width() - @char_w * byte_size(clock), 2)

    {:text, x, @status_y, :default16px, @caption, @bar, clock}
  end
end
