require 'app_helper'

RSpec.describe EDF do
  before { $cache.clear } # make sure we hit the VCR cassette

  describe ".tempo_color_for" do
    it "returns correct color for the period" do
      VCR.use_cassette("tempo 2025-02-02 blue-red-white") do
        time = Time.new(2025, 2, 3, 6, 0, 0, "+01:00") # 6am: beginning of tempo RED period
        expect(EDF.tempo_color_for(time-1)).to eq(BLUE)
        expect(EDF.tempo_color_for(time)).to eq(RED)
        time += (22-6).hours # 10pm: end of on-duty hours
        expect(EDF.tempo_color_for(time)).to eq(RED)
        time += 2.hours # 0am: next day but still in the RED period
        expect(EDF.tempo_color_for(time)).to eq(RED)
        time += 6.hours # 6am: beginning next period (WHITE)
        expect(EDF.tempo_color_for(time-1)).to eq(RED)
        expect(EDF.tempo_color_for(time)).to eq(WHITE)
      end
    end

    it "returns unknown for the future" do
      VCR.use_cassette("tempo 2025-02-12 unknown") do
        time = Time.new(2025, 2, 12, 6, 0, 0, "+01:00") # recorded on 2025-03-11
        expect(EDF.tempo_color_for(time)).to eq(UNKNOWN)
      end
    end
  end

  describe ".ejp_color_for" do
    it "returns correct color for the period" do
      VCR.use_cassette("ejp 2025-02-06 green-red-green") do
        time = Time.new(2025, 2, 7, 0, 0, 0, "+00:00") # 1am Paris (0am London): beginning of EJP RED period
        expect(EDF.ejp_color_for(time-1)).to eq(GREEN)
        expect(EDF.ejp_color_for(time)).to eq(RED)
        time += 23.hours # 0am Paris: next day but still in the RED period
        expect(EDF.ejp_color_for(time)).to eq(RED)
        time += 1.hours # 1am Paris: beginning next period (GREEN)
        expect(EDF.ejp_color_for(time-1)).to eq(RED)
        expect(EDF.ejp_color_for(time)).to eq(GREEN)
      end
    end

    it "returns unknown for tomorrow before 15:00 (if GREEN)" do
      VCR.use_cassette("ejp 2025-02-06 green-red-green", record: :none) do
        time = Time.new(2025, 2, 6, 0, 0, 0, "+00:00") # 1am Paris (0am London): beginning of EJP GREEN period
        allow(Date).to receive(:today) { Date.new(2025, 2, 5) } # and we're currently the day before
        expect(EDF.ejp_color_for(time)).to eq(UNKNOWN)
        time += 14.hours # 3pm Paris: time to publish the "GREEN" status
        expect(EDF.ejp_color_for(time-1)).to eq(UNKNOWN)
        expect(EDF.ejp_color_for(time)).to eq(GREEN)
        time += 10.hours # 1am Paris: beginning of EJP RED period
        allow(Date).to receive(:today) { Date.new(2025, 2, 6) }
        expect(EDF.ejp_color_for(time)).to eq(RED) # no delay here we can announce the RED
        time += 14.hours # 3pm Paris: already RED, still RED
        expect(EDF.ejp_color_for(time-1)).to eq(RED)
        expect(EDF.ejp_color_for(time)).to eq(RED)
      end
    end
  end
end