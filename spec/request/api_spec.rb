require 'app_helper'

RSpec.describe '/' do
  let(:json) { JSON.parse(last_response.body) }

  context "in TEMPO mode" do
    before do
      travel_to Time.new(2025, 2, 3, 6, 0, 0, "+01:00")
    end

    it "returns expected colors during HP (hitting real data)" do
      stub_const("EDF::TEMPO_API", :couleur)
      VCR.use_cassette("tempo 2025-02-02 blue-red-white", record: :none) do
        get '/'
      end
      expect(last_response).to be_ok
      expect(json['time']).to eq('2025-02-03T05:00:00Z')
      expect(json['mode']).to eq('tempo')
      # initial: RED (+effect) then WHITE
      expect(json['actions']).to include({"action"=>"updateLEDs", "timing"=>"initial", "topLEDs"=>{"RGB"=>[255, 0, 0], "FX"=>"breathingRingHalf"}, "bottomLEDs"=>{"RGB"=>[220, 190, 160], "FX"=>"none"}})
      # at 22:00 → off duty darker RED (no effect) then darker WHITE
      expect(json['actions']).to include({"action"=>"updateLEDs", "timing"=>"2025-02-03T21:00:00Z", "topLEDs"=>{"RGB"=>[127, 0, 0], "FX"=>"none"}, "bottomLEDs"=>{"RGB"=>[110, 95, 80], "FX"=>"none"}})
      # at 06:00 the next day → WHITE then UNKNOWN
      expect(json['actions']).to include({"action"=>"updateLEDs", "timing"=>"2025-02-04T05:00:00Z", "topLEDs"=>{"RGB"=>[220, 190, 160], "FX"=>"none"}, "bottomLEDs"=>{"RGB"=>[0, 0, 0], "FX"=>"none"}})
      # at 22:00 the next day → dark WHITE then UNKNOWN
      expect(json['actions']).to include({"action"=>"updateLEDs", "timing"=>"2025-02-04T21:00:00Z", "topLEDs"=>{"RGB"=>[110, 95, 80], "FX"=>"none"}, "bottomLEDs"=>{"RGB"=>[0, 0, 0], "FX"=>"none"}})
      # No more data after the next day
      expect(json['actions']).to include({"action"=>"error_noData", "timing"=>"2025-02-05T05:00:00Z"})
      # Next sync in 1h+jitter
      expect(json['actions']).to include({"action"=>"syncAPI", "timing"=>/2025-02-03T06:\d\d:\d\dZ/})
    end

    it "returns expected colors during HP (from params)" do
      get '/', today: BLUE, tomorrow: UNKNOWN
      expect(last_response).to be_ok
      expect(json['time']).to eq('2025-02-03T05:00:00Z')
      # initial: BLUE (no effect) then UNKNOWN
      expect(json['actions']).to include({"action"=>"updateLEDs", "timing"=>"initial", "topLEDs"=>{"RGB"=>[12, 105, 255], "FX"=>"none"}, "bottomLEDs"=>{"RGB"=>[0, 0, 0], "FX"=>"none"}})
      # at 22:00 → off duty darker BLUE (no effect) then UNKNOWN
      expect(json['actions']).to include({"action"=>"updateLEDs", "timing"=>"2025-02-03T21:00:00Z", "topLEDs"=>{"RGB"=>[6, 52, 127], "FX"=>"none"}, "bottomLEDs"=>{"RGB"=>[0, 0, 0], "FX"=>"none"}})
      # at 06:00 the next day → No more data
      expect(json['actions']).to include({"action"=>"error_noData", "timing"=>"2025-02-04T05:00:00Z"})
      # Next sync in 1h+jitter
      expect(json['actions']).to include({"action"=>"syncAPI", "timing"=>/2025-02-03T06:\d\d:\d\dZ/})
    end

    it "returns expected colors during HC (from params)" do
      travel 16.hours # moving from 06:00 to 22:00
      get '/', today: RED, tomorrow: UNKNOWN
      expect(last_response).to be_ok
      expect(json['time']).to eq('2025-02-03T21:00:00Z')
      # initial: off duty darker RED (no effect) then UNKNOWN
      expect(json['actions']).to include({"action"=>"updateLEDs", "timing"=>"initial", "topLEDs"=>{"RGB"=>[127, 0, 0], "FX"=>"none"}, "bottomLEDs"=>{"RGB"=>[0, 0, 0], "FX"=>"none"}})
      # at 06:00 the next day → No more data
      expect(json['actions']).to include({"action"=>"error_noData", "timing"=>"2025-02-04T05:00:00Z"})
      # Next sync in 1h+jitter
      expect(json['actions']).to include({"action"=>"syncAPI", "timing"=>/2025-02-03T22:\d\d:\d\dZ/})
    end
  end

  context "in EJP mode" do
    before do
      travel_to Time.new(2025, 2, 7, 1, 0, 0, "+01:00")
    end

    it "returns expected colors during HC (hitting real data)" do
      VCR.use_cassette("ejp 2025-02-06 green-red-green", record: :none) do
        get '/', mode: 'ejp'
      end
      expect(last_response).to be_ok
      expect(json['time']).to eq('2025-02-07T00:00:00Z')
      expect(json['mode']).to eq('ejp')
      # initial: off duty darker RED (no effect) then UNDEFINED
      expect(json['actions']).to include({"action"=>"updateLEDs", "timing"=>"initial", "topLEDs"=>{"RGB"=>[127, 0, 0], "FX"=>"none"}, "bottomLEDs"=>{"RGB"=>[0, 0, 0], "FX"=>"none"}})
      # at 07:00 → on duty RED (+effect) then UNDEFINED
      expect(json['actions']).to include({"action"=>"updateLEDs", "timing"=>"2025-02-07T06:00:00Z", "topLEDs"=>{"RGB"=>[255, 0, 0], "FX"=>"breathingRingHalf"}, "bottomLEDs"=>{"RGB"=>[0, 0, 0], "FX"=>"none"}})
      # Next sync (quicker) in 30m+jitter (to get the RED if it gets announced earlier)
      expect(json['actions']).to include({"action"=>"syncAPI", "timing"=>/2025-02-07T00:[345]\d:\d\dZ/})
      # No more data after 1am end of day (refresh should bring it before that)
      expect(json['actions']).to include({"action"=>"error_noData", "timing"=>"2025-02-08T00:00:00Z"})
    end

    it "returns expected colors during HP (from params)" do
      travel 16.hours # moving from 01:00 to 17:00
      get '/', mode: 'ejp', today: GREEN, tomorrow: RED
      expect(last_response).to be_ok
      expect(json['time']).to eq('2025-02-07T16:00:00Z')
      # initial: on duty GREEN (no effect) then RED
      expect(json['actions']).to include({"action"=>"updateLEDs", "timing"=>"initial", "topLEDs"=>{"RGB"=>[30, 200, 0], "FX"=>"none"}, "bottomLEDs"=>{"RGB"=>[255, 0, 0], "FX"=>"none"}})
      # at 01:00 → off duty RED (no effect) then UNDEFINED
      expect(json['actions']).to include({"action"=>"updateLEDs", "timing"=>"2025-02-08T00:00:00Z", "topLEDs"=>{"RGB"=>[127, 0, 0], "FX"=>"none"}, "bottomLEDs"=>{"RGB"=>[0, 0, 0], "FX"=>"none"}})
      # at 07:00 → on duty RED (+effect) then UNDEFINED
      expect(json['actions']).to include({"action"=>"updateLEDs", "timing"=>"2025-02-08T06:00:00Z", "topLEDs"=>{"RGB"=>[255, 0, 0], "FX"=>"breathingRingHalf"}, "bottomLEDs"=>{"RGB"=>[0, 0, 0], "FX"=>"none"}})
      # No more data after 1am end of tomorrow
      expect(json['actions']).to include({"action"=>"error_noData", "timing"=>"2025-02-09T00:00:00Z"})
      # Next sync in 1h+jitter
      expect(json['actions']).to include({"action"=>"syncAPI", "timing"=>/2025-02-07T17:\d\d:\d\dZ/})
    end

    it "provides a custom syncAPI at 3pm before announce" do
      travel 13.hours + 30.minutes # moving from 01:00 to 14:30
      get '/', mode: 'ejp', today: RED, tomorrow: UNKNOWN
      expect(last_response).to be_ok
      expect(json['time']).to eq('2025-02-07T13:30:00Z')
      # initial: on duty RED (+effect) then UNDEFINED
      expect(json['actions']).to include({"action"=>"updateLEDs", "timing"=>"initial", "topLEDs"=>{"RGB"=>[255, 0, 0], "FX"=>"breathingRingHalf"}, "bottomLEDs"=>{"RGB"=>[0, 0, 0], "FX"=>"none"}})
      # Special next sync at 15:00 +small jitter to fetch TOMORROW value
      expect(json['actions']).to include({"action"=>"syncAPI", "timing"=>/2025-02-07T14:00:\d\dZ/})
      # No more data after 1am end of day (refresh should bring it before that)
      expect(json['actions']).to include({"action"=>"error_noData", "timing"=>"2025-02-08T00:00:00Z"})
    end

    it "provides a normal syncAPI after 3pm if tomorrow is still UNKNOWN (likely a bug)" do
      travel 14.hours # moving from 01:00 to 15:00
      get '/', mode: 'ejp', today: RED, tomorrow: UNKNOWN
      expect(last_response).to be_ok
      expect(json['time']).to eq('2025-02-07T14:00:00Z')
      # initial: on duty RED (+effect) then UNDEFINED
      expect(json['actions']).to include({"action"=>"updateLEDs", "timing"=>"initial", "topLEDs"=>{"RGB"=>[255, 0, 0], "FX"=>"breathingRingHalf"}, "bottomLEDs"=>{"RGB"=>[0, 0, 0], "FX"=>"none"}})
      # Next sync (quicker) in 30m+jitter (to get the late color)
      expect(json['actions']).to include({"action"=>"syncAPI", "timing"=>/2025-02-07T14:[345]\d:\d\dZ/})
      # No more data after 1am end of day (refresh should bring it before that)
      expect(json['actions']).to include({"action"=>"error_noData", "timing"=>"2025-02-08T00:00:00Z"})
    end
  end

  context "with a device id" do
    it "creates a device if never seen" do
      expect {
        get '/', id: '123', today: RED, tomorrow: UNKNOWN
        expect(last_response).to be_ok
        expect(json['mode']).to eq('tempo')
      }.to change(Device, :count).by(1)
      d = Device.find(123)
      expect(d.mode).to eq('tempo')
    end

    it "updates device if existing + honor configured mode" do
      d = Device.create!(id: 124, mode: 'ejp', created_at: 1.day.ago, updated_at: 1.day.ago)
      expect {
        get '/', id: '124', today: RED, tomorrow: UNKNOWN
        expect(last_response).to be_ok
        expect(json['mode']).to eq('ejp')
      }.to change { d.reload.updated_at }
      expect(d.created_at).to eq(1.day.ago) # no change
      expect(d.mode).to eq('ejp') # no change
    end
  end
end
