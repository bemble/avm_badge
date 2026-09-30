defmodule Badge.BrandsTest do
  use ExUnit.Case, async: true

  alias Badge.Brands

  @brands [:home_assistant, :nabu_casa]

  defp file(brand), do: "assets/brands/#{brand}@40x40.rgba"

  describe "normalise/1" do
    test "lowercases letters and drops everything else" do
      assert Brands.normalise("Nabu Casa") == "nabucasa"
      assert Brands.normalise("@NABU-casa!") == "nabucasa"
      assert Brands.normalise(" Home  Assistant 2024 ") == "homeassistant2024"
    end

    test "drops bytes above ASCII, and an absent value is empty" do
      assert Brands.normalise("Caf" <> <<0xC3, 0xA9>>) == "caf"
      assert Brands.normalise("") == ""
      assert Brands.normalise(nil) == ""
    end
  end

  describe "logos/1" do
    test "a Nabu Casa company brings its logo to the company line" do
      assert Brands.logos(%{company: "Nabu Casa"}) == [{:company, :nabu_casa}]
      assert Brands.logos(%{company: "@nabucasa"}) == [{:company, :nabu_casa}]
    end

    test "any hobby of Home Assistant brings its logo to the hobbies line" do
      assert Brands.logos(%{hobbies: "synths, home-assistant, coffee"}) ==
               [{:hobbies, :home_assistant}]
    end

    test "both at once, company first" do
      assert Brands.logos(%{company: "Nabu Casa", hobbies: "Home Assistant"}) ==
               [{:company, :nabu_casa}, {:hobbies, :home_assistant}]
    end

    test "only an exact match counts" do
      assert Brands.logos(%{company: "Nabu Casa Inc", hobbies: "Home Assistant Cloud"}) == []
      assert Brands.logos(%{company: "Home Assistant", hobbies: "Nabu Casa"}) == []
      assert Brands.logos(%{}) == []
      assert Brands.logos(%{company: nil, hobbies: nil}) == []
    end
  end

  describe "the logos" do
    test "every file is a 40x40 picture" do
      for brand <- @brands, do: assert(byte_size(File.read!(file(brand))) == 40 * 40 * 4)
      assert Brands.size() == 40
    end

    test "carry real alpha, clear round the edge and solid inside" do
      for brand <- @brands do
        alphas = for <<_r, _g, _b, a <- File.read!(file(brand))>>, do: a

        assert hd(alphas) == 0
        assert 0xFF in alphas
      end
    end

    test "the image is the bytes the partition answers, or nil without them" do
      bytes = File.read!(file(:nabu_casa))

      assert Brands.picture(bytes) == {:rgba8888, 40, 40, bytes}
      assert Brands.picture(:undefined) == nil
      assert Brands.picture(<<0, 0, 0, 0>>) == nil
    end

    test "reads each logo from the assets partition" do
      for brand <- @brands do
        assert Brands.image(brand) == {:rgba8888, 40, 40, File.read!(file(brand))}
      end
    end
  end
end
