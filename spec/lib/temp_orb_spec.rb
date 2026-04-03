require 'app_helper'

RSpec.describe TempOrb do
  describe ".dim_leds" do
    it "halves RGB values" do
      expect(TempOrb.dim_leds(RGB: [220, 172, 120], FX: "none")).to eq(RGB: [110, 86, 60], FX: "none")
    end

    it "halves secondaryRGB when present" do
      leds = { RGB: [220, 172, 120], FX: "breathingRingHalf", secondaryRGB: [255, 0, 0] }
      expect(TempOrb.dim_leds(leds)).to eq(RGB: [110, 86, 60], FX: "breathingRingHalf", secondaryRGB: [127, 0, 0])
    end

    it "does not mutate the original" do
      original = { RGB: [200, 100, 50], FX: "none" }
      TempOrb.dim_leds(original)
      expect(original[:RGB]).to eq([200, 100, 50])
    end
  end

  describe ".dim_action" do
    it "dims both topLEDs and bottomLEDs" do
      action = {
        action: "updateLEDs", timing: "initial",
        topLEDs: { RGB: [255, 0, 0], FX: "breathingRingHalf" },
        bottomLEDs: { RGB: [12, 105, 255], FX: "none" },
      }
      dimmed = TempOrb.dim_action(action)
      expect(dimmed[:topLEDs]).to eq(RGB: [127, 0, 0], FX: "breathingRingHalf")
      expect(dimmed[:bottomLEDs]).to eq(RGB: [6, 52, 127], FX: "none")
    end

    it "preserves timing and action type" do
      action = {
        action: "updateLEDs", timing: "2026-01-09T19:00:00Z",
        topLEDs: { RGB: [100, 100, 100], FX: "none" },
        bottomLEDs: { RGB: [100, 100, 100], FX: "none" },
      }
      dimmed = TempOrb.dim_action(action)
      expect(dimmed[:action]).to eq("updateLEDs")
      expect(dimmed[:timing]).to eq("2026-01-09T19:00:00Z")
    end

    it "handles secondaryRGB" do
      action = {
        action: "updateLEDs", timing: "initial",
        topLEDs: { RGB: COLORS[BONIF][0..2], FX: "none", secondaryRGB: [255, 0, 0] },
        bottomLEDs: { RGB: [12, 105, 255], FX: "none" },
      }
      dimmed = TempOrb.dim_action(action)
      expect(dimmed[:topLEDs][:secondaryRGB]).to eq([127, 0, 0])
    end

    it "does not mutate the original" do
      action = {
        action: "updateLEDs", timing: "initial",
        topLEDs: { RGB: [200, 100, 50], FX: "none" },
        bottomLEDs: { RGB: [100, 200, 50], FX: "none" },
      }
      TempOrb.dim_action(action)
      expect(action[:topLEDs][:RGB]).to eq([200, 100, 50])
      expect(action[:bottomLEDs][:RGB]).to eq([100, 200, 50])
    end
  end

  describe ".apply_dimming" do
    # Winter: sunrise 08:42 (clamped to 08:00), sunset 17:13 (clamped to 20:00)
    # Summer: sunrise 05:46 (unclamped), sunset 21:57 (unclamped)

    let(:red_blue_action) {
      { action: "updateLEDs", timing: "initial",
        topLEDs: { RGB: COLORS[RED], FX: "none" }, bottomLEDs: { RGB: COLORS[BLUE], FX: "none" } }
    }

    it "dims actions during night (winter, 21h)" do
      travel_to Time.new(2026, 1, 9, 21, 0, 0, "+01:00") # 21:00 CET, after clamped sunset (20:00)
      result = TempOrb.apply_dimming([red_blue_action], Time.now)
      led = result.find { _1[:timing] == "initial" }
      expect(led[:topLEDs][:RGB]).to eq(COLORS[RED].map { _1 / 2 })
      expect(led[:bottomLEDs][:RGB]).to eq(COLORS[BLUE].map { _1 / 2 })
    end

    it "does not dim actions during daytime (winter, 15h)" do
      travel_to Time.new(2026, 1, 9, 15, 0, 0, "+01:00") # 15:00 CET, before clamped sunset
      result = TempOrb.apply_dimming([red_blue_action], Time.now)
      led = result.find { _1[:timing] == "initial" }
      expect(led[:topLEDs][:RGB]).to eq(COLORS[RED])
      expect(led[:bottomLEDs][:RGB]).to eq(COLORS[BLUE])
    end

    it "inserts sunset transition action (summer)" do
      travel_to Time.new(2026, 6, 20, 20, 0, 0, "+02:00") # 20:00 CEST, before sunset ~21:57
      bright_action = { **red_blue_action, timing: Time.now.utc.iso8601 }
      result = TempOrb.apply_dimming([bright_action], Time.now)
      sunset_action = result.find { _1[:timing] == "2026-06-20T19:57:00Z" }
      expect(sunset_action).to be_present
      expect(sunset_action[:topLEDs][:RGB]).to eq(COLORS[RED].map { _1 / 2 })
    end

    it "inserts sunrise transition action (summer)" do
      travel_to Time.new(2026, 6, 20, 3, 0, 0, "+02:00") # 03:00 CEST, before sunrise ~05:46
      night_action = { **red_blue_action, timing: Time.now.utc.iso8601 }
      result = TempOrb.apply_dimming([night_action], Time.now)
      sunrise_action = result.find { _1[:timing] == "2026-06-20T03:46:00Z" }
      expect(sunrise_action).to be_present
      expect(sunrise_action[:topLEDs][:RGB]).to eq(COLORS[RED]) # full brightness
    end

    it "does not touch non-LED actions" do
      travel_to Time.new(2026, 1, 9, 22, 0, 0, "+01:00")
      sync = { action: "syncAPI", timing: "2026-01-09T22:30:00Z" }
      result = TempOrb.apply_dimming([red_blue_action, sync], Time.now)
      expect(result).to include(sync)
    end
  end
end
