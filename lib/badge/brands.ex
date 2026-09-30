defmodule Badge.Brands do
  @moduledoc """
  Logos the Name page's live screen shows now and then in place of a line.

  A company of Nabu Casa brings the Nabu Casa logo to the company line, and
  a hobby of Home Assistant the Home Assistant logo to the hobbies line,
  matched ignoring case, spaces and punctuation. Each logo is a square
  `rgba8888` file with real alpha in `assets/brands`, named
  `<brand>@<size>x<size>.rgba`, read from the assets partition, so
  `image/1` is `nil` on a badge without one. Regenerate them with
  `tools/brands.py`.
  """

  @compile {:no_warn_undefined, :atomvm}

  alias Badge.Marquee

  @size 40
  @dir Path.expand("../../assets/brands", __DIR__)

  @external_resource @dir

  for brand <- [:home_assistant, :nabu_casa] do
    file = Path.join(@dir, "#{brand}@#{@size}x#{@size}.rgba")

    @external_resource file

    File.exists?(file) || raise "no #{Path.basename(file)} in #{@dir}; run tools/brands.py"

    byte_size(File.read!(file)) == @size * @size * 4 ||
      raise "#{Path.basename(file)}: expected #{@size * @size * 4} bytes"

    defp path(unquote(brand)), do: unquote(~c"brands/" ++ String.to_charlist(Path.basename(file)))
  end

  @doc "The logos' width and height, in pixels."
  @spec size() :: pos_integer
  def size, do: @size

  @doc "Which live-screen lines of `profile` have a logo, as `{key, brand}`."
  @spec logos(map) :: [{:company | :hobbies, atom}]
  def logos(profile) do
    company =
      case normalise(Map.get(profile, :company)) do
        "nabucasa" -> [{:company, :nabu_casa}]
        _other -> []
      end

    hobbies = Marquee.hobbies(Map.get(profile, :hobbies))

    hobbies =
      case :lists.any(&(normalise(&1) == "homeassistant"), hobbies) do
        true -> [{:hobbies, :home_assistant}]
        false -> []
      end

    company ++ hobbies
  end

  @doc "`text` with ASCII letters lowercased and everything but letters and digits dropped."
  @spec normalise(binary | nil) :: binary
  def normalise(nil), do: <<>>
  def normalise(text), do: normalise(text, <<>>)

  defp normalise(<<>>, acc), do: acc

  defp normalise(<<char, rest::binary>>, acc) when char >= ?A and char <= ?Z,
    do: normalise(rest, <<acc::binary, char + 32>>)

  defp normalise(<<char, rest::binary>>, acc)
       when (char >= ?a and char <= ?z) or (char >= ?0 and char <= ?9),
       do: normalise(rest, <<acc::binary, char>>)

  defp normalise(<<_char, rest::binary>>, acc), do: normalise(rest, acc)

  @doc "A brand's logo as an image, read from the assets partition, or `nil` without one."
  @spec image(atom) :: {:rgba8888, pos_integer, pos_integer, binary} | nil
  def image(brand), do: picture(read(brand))

  @doc "The image from what `:atomvm.read_priv/2` answered: `nil` unless it is the bytes."
  @spec picture(binary | :undefined) :: {:rgba8888, pos_integer, pos_integer, binary} | nil
  def picture(bytes) when is_binary(bytes) and byte_size(bytes) == @size * @size * 4,
    do: {:rgba8888, @size, @size, bytes}

  def picture(_absent), do: nil

  defp read(brand) do
    :atomvm.read_priv(:assets, path(brand))
  catch
    _kind, _error -> :undefined
  end
end
