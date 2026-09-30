defmodule Badge.AccelTest do
  use ExUnit.Case, async: true

  alias Badge.Accel

  describe "decode/1" do
    test "converts raw counts to milli-g in the panel's frame" do
      bytes = <<-1120::little-signed-16, 13936::little-signed-16, -9184::little-signed-16>>
      assert Accel.decode(bytes) == {68, 850, 560}
    end

    test "a badge lying face up reads gravity out of the screen" do
      bytes = <<0::little-signed-16, 0::little-signed-16, -16384::little-signed-16>>
      assert Accel.decode(bytes) == {0, 0, 1000}
    end

    test "the sensor's y runs toward the panel's top edge" do
      bytes = <<0::little-signed-16, 16384::little-signed-16, 0::little-signed-16>>
      assert Accel.decode(bytes) == {0, 1000, 0}
    end

    test "the sensor's x runs toward the panel's left edge" do
      bytes = <<16384::little-signed-16, 0::little-signed-16, 0::little-signed-16>>
      assert Accel.decode(bytes) == {-1000, 0, 0}
    end

    test "a stationary reading has unit magnitude" do
      # Real probe reading of a badge sitting flat on a desk.
      bytes = <<-1120::little-signed-16, 13936::little-signed-16, -9184::little-signed-16>>
      {x, y, z} = Accel.decode(bytes)
      magnitude = :math.sqrt(x * x + y * y + z * z)

      assert_in_delta magnitude, 1000, 30
    end
  end

  describe "average/2" do
    test "nil previous adopts the sample as-is" do
      assert Accel.average(nil, {100, 200, 300}) == {100, 200, 300}
    end

    test "a repeated sample settles near it and then stops moving" do
      settle = fn n ->
        :lists.foldl(
          fn _i, acc -> Accel.average(acc, {100, 200, 300}) end,
          {0, 0, 0},
          :lists.seq(1, n)
        )
      end

      {x, y, z} = settle.(40)

      # Integer division truncates, so the average stalls within 3 of the target
      # rather than reaching it. That is what stops it dithering once settled.
      assert_in_delta x, 100, 3
      assert_in_delta y, 200, 3
      assert_in_delta z, 300, 3

      assert settle.(80) == settle.(40)
    end

    test "one step moves a quarter of the way" do
      assert Accel.average({0, 0, 0}, {100, 200, 300}) == {25, 50, 75}
    end
  end

  describe "orientation/1" do
    test "face up and level gives zero roll and pitch" do
      assert Accel.orientation({0, 0, 1000}) == {0, 0}
    end

    test "lowering the right edge rolls positive" do
      assert Accel.orientation({-1000, 0, 0}) == {90, 0}
      assert Accel.orientation({-500, 0, 866}) == {30, 0}
    end

    test "raising the top edge pitches positive" do
      assert Accel.orientation({0, 1000, 0}) == {0, 90}
      assert Accel.orientation({0, 500, 866}) == {0, 30}
    end

    test "tipping the top edge away pitches negative, with no roll" do
      assert Accel.orientation({0, -500, 866}) == {0, -30}
    end
  end

  describe "motion interrupt registers" do
    test "a threshold is counted in 16 mg steps, rounded to the nearest" do
      assert Accel.threshold(320) == 20
      assert Accel.threshold(300) == 19
      assert Accel.threshold(16) == 1
    end

    test "a threshold never reaches zero, which would fire on noise, nor overflows 7 bits" do
      assert Accel.threshold(1) == 1
      assert Accel.threshold(4_000) == 127
    end

    test "a duration is counted in samples at the output data rate" do
      assert Accel.duration(80, 25) == 2
      assert Accel.duration(40, 25) == 1
      assert Accel.duration(0, 25) == 0
      assert Accel.duration(60_000, 25) == 127
    end

    test "only INT1_SRC's IA bit means a motion event" do
      assert Accel.moved?(0x40)
      assert Accel.moved?(0x6A)
      refute Accel.moved?(0x2A)
      refute Accel.moved?(0x00)
    end
  end
end
