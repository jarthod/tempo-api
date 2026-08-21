require 'app_helper'

RSpec.describe EDF do
  describe ".tempo_color_for" do
    context "(using api-couleur-tempo.fr)" do
      it "returns correct color for the period" do
        VCR.use_cassette("tempo 2025-02-02 blue-red-white") do
          expect(EDF.tempo_color_for(Date.new(2025, 2, 2), api: 'api-couleur-tempo.fr')).to eq(BLUE)
          expect(EDF.tempo_color_for(Date.new(2025, 2, 3), api: 'api-couleur-tempo.fr')).to eq(RED)
          expect(EDF.tempo_color_for(Date.new(2025, 2, 4), api: 'api-couleur-tempo.fr')).to eq(WHITE)
        end
      end

      it "returns unknown for the future" do
        VCR.use_cassette("tempo 2025-02-12 unknown") do # recorded on 2025-03-11
          expect(EDF.tempo_color_for(Date.new(2025, 2, 12), api: 'api-couleur-tempo.fr')).to eq(UNKNOWN)
        end
      end

      it "returns unknown on errors" do
        expect(EDF).to receive(:get_json).and_return(error: "test")
        expect(EDF.tempo_color_for(Date.today, api: 'api-couleur-tempo.fr')).to eq(UNKNOWN)
      end
    end

    context "(using services-rte.com)" do
      it "returns correct color for the period" do
        VCR.use_cassette("tempo RTE 2025-02-22") do
          # we can't go back in time with this API
          expect(EDF.tempo_color_for(Date.new(2025, 2, 21), api: 'services-rte.com')).to eq(UNKNOWN)
          expect(EDF.tempo_color_for(Date.new(2025, 2, 22), api: 'services-rte.com')).to eq(BLUE)
          expect(EDF.tempo_color_for(Date.new(2025, 2, 23), api: 'services-rte.com')).to eq(BLUE)
        end
      end

      # it "returns unknown for the future" do
      #   VCR.use_cassette("tempo 2025-02-12 unknown") do
      #     time = Time.new(2025, 2, 12, 6, 0, 0, "+01:00") # recorded on 2025-03-11
      #     expect(EDF.tempo_color_for(time)).to eq(UNKNOWN)
      #   end
      # end

      it "returns unknown on errors" do
        expect(EDF).to receive(:get_json).and_return(error: "test")
        expect(EDF.tempo_color_for(Time.now, api: 'services-rte.com')).to eq(UNKNOWN)
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

  describe ".zen_flex_color_for" do
    it "maps RAS to ECO and ZENF_PM to RED" do
      VCR.use_cassette("zen_flex 2026-01-08 sobriety-eco") do
        expect(EDF.zen_flex_color_for(Date.new(2026, 1, 9))).to eq(RED)
        expect(EDF.zen_flex_color_for(Date.new(2026, 1, 10))).to eq(ECO)
      end
    end

    it "maps ZENF_BONIF to BONIF (hitting real data)" do
      VCR.use_cassette("zen_flex 2025-03-18 bonif") do
        expect(EDF.zen_flex_color_for(Date.new(2025, 3, 18))).to eq(BONIF)
      end
    end

    it "maps ZENF_BONUS to BONUS (hitting real data)" do
      VCR.use_cassette("zen_flex 2025-10-16 bonus") do
        expect(EDF.zen_flex_color_for(Date.new(2025, 10, 16))).to eq(BONUS)
      end
    end

    it "maps NON_DETERMINE to UNKNOWN" do
      VCR.use_cassette("zen_flex 2030-01-01 unknown") do
        expect(EDF.zen_flex_color_for(Date.new(2030, 1, 1))).to eq(UNKNOWN)
      end
    end

    it "returns unknown on errors" do
      expect(EDF).to receive(:get_json).and_return(error: "test")
      expect(EDF.zen_flex_color_for(Date.today)).to eq(UNKNOWN)
    end
  end
end