require 'app_helper'

RSpec.describe EDF do
  describe ".cached_tempo_color_for" do
    it "returns correct color for the period" do
      VCR.use_cassette("tempo 2025-02-02 blue-red-white") do
        time = Time.new(2025, 2, 3, 6, 0, 0, "+01:00") # 6am: beginning of tempo RED period
        expect(EDF.cached_tempo_color_for(time-1)).to eq(BLUE)
        expect(EDF.cached_tempo_color_for(time)).to eq(RED)
        time += (22-6).hours # 10pm: end of on-duty hours
        expect(EDF.cached_tempo_color_for(time)).to eq(RED)
        time += 2.hours # 0am: next day but still in the RED period
        expect(EDF.cached_tempo_color_for(time)).to eq(RED)
        time += 6.hours # 6am: beginning next period (WHITE)
        expect(EDF.cached_tempo_color_for(time-1)).to eq(RED)
        expect(EDF.cached_tempo_color_for(time)).to eq(WHITE)
      end
      # entries are cached
      expect($cache.read("tempo_color/2025-02-02")).to eq(BLUE)
      expect($cache.read("tempo_color/2025-02-03")).to eq(RED)
      expect($cache.read("tempo_color/2025-02-04")).to eq(WHITE)
    end

    it "returns unknown for the future (no cache)" do
      date = Date.new(2025, 2, 12)
      expect(EDF).to receive(:tempo_color_for).with(date, api: 'api-couleur-tempo.fr').once.and_call_original
      expect(EDF).to receive(:tempo_color_for).with(date, api: 'services-rte.com').once.and_return(UNKNOWN)
      VCR.use_cassette("tempo 2025-02-12 unknown") do
        time = Time.new(2025, 2, 12, 6, 0, 0, "+01:00") # recorded on 2025-03-11
        expect(EDF.cached_tempo_color_for(time)).to eq(UNKNOWN)
      end
      # entry is NOT cached (never cache UNKNOWN)
      expect($cache.read("tempo_color/2025-02-12")).to be_nil
    end

    it "falls back to second API if needed" do
      expect(EDF).to receive(:tempo_color_for).with(instance_of(Date), api: 'api-couleur-tempo.fr').exactly(3).times.and_return(UNKNOWN)
      expect(EDF).to receive(:tempo_color_for).with(instance_of(Date), api: 'services-rte.com').exactly(3).times.and_call_original
      VCR.use_cassette("tempo RTE 2025-02-22") do
        time = Time.new(2025, 2, 22, 6, 0, 0, "+01:00") # 6am: beginning of tempo RED period
        expect(EDF.cached_tempo_color_for(time-1)).to eq(UNKNOWN)
        expect(EDF.cached_tempo_color_for(time)).to eq(BLUE)
        expect(EDF.cached_tempo_color_for(time+1.day)).to eq(BLUE)
      end
      # entries are cached
      expect($cache.read("tempo_color/2025-02-21")).to be_nil
      expect($cache.read("tempo_color/2025-02-22")).to eq(BLUE)
      expect($cache.read("tempo_color/2025-02-23")).to eq(BLUE)
    end

    it "returns unknown on errors" do
      expect(EDF).to receive(:get_json).twice.and_return(error: "test") # both API tried
      expect(EDF.cached_tempo_color_for(Time.now)).to eq(UNKNOWN)
    end
  end

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

  describe ".cached_ejp_color_for" do
    it "returns correct color for the period" do
      VCR.use_cassette("ejp 2025-02-06 green-red-green") do
        time = Time.new(2025, 2, 7, 0, 0, 0, "+00:00") # 1am Paris (0am London): beginning of EJP RED period
        expect(EDF.cached_ejp_color_for(time-1)).to eq(GREEN)
        expect(EDF.cached_ejp_color_for(time)).to eq(RED)
        time += 23.hours # 0am Paris: next day but still in the RED period
        expect(EDF.cached_ejp_color_for(time)).to eq(RED)
        time += 1.hours # 1am Paris: beginning next period (GREEN)
        expect(EDF.cached_ejp_color_for(time-1)).to eq(RED)
        expect(EDF.cached_ejp_color_for(time)).to eq(GREEN)
      end
      # entries are cached
      expect($cache.read("ejp_color/2025-02-06")).to eq(GREEN)
      expect($cache.read("ejp_color/2025-02-07")).to eq(RED)
      expect($cache.read("ejp_color/2025-02-08")).to eq(GREEN)
    end

    it "returns unknown for the future (no cache)" do
      expect(EDF).to receive(:ejp_color_for).once.and_return(UNKNOWN)
      time = Time.new(2035, 2, 12, 6, 0, 0, "+01:00")
      expect(EDF.cached_ejp_color_for(time)).to eq(UNKNOWN)
      # entry is NOT cached (never cache UNKNOWN)
      expect($cache.read("ejp_color/2035-02-12")).to be_nil
    end

    it "falls back to green outside of EJP period" do
      expect(EDF).to receive(:ejp_color_for).exactly(2).times.and_return(RED)
      expect(EDF.cached_ejp_color_for(Time.new(2025, 3, 31, 6))).to eq(RED)
      expect(EDF.cached_ejp_color_for(Time.new(2025, 4, 1, 6))).to eq(GREEN) # outside period
      expect(EDF.cached_ejp_color_for(Time.new(2025, 10, 31, 6))).to eq(GREEN) # outside period
      expect(EDF.cached_ejp_color_for(Time.new(2025, 11, 1, 6))).to eq(RED)
      # entries are cached
      expect($cache.read("ejp_color/2025-03-31")).to eq(RED)
      expect($cache.read("ejp_color/2025-04-01")).to be_nil # not cached
      expect($cache.read("ejp_color/2025-10-31")).to be_nil # not cached
      expect($cache.read("ejp_color/2025-11-01")).to eq(RED)
    end

    it "returns unknown on errors" do
      expect(EDF).to receive(:get_json).and_return(error: "test") # both API tried
      expect(EDF.cached_ejp_color_for(Time.new(2025, 2, 2))).to eq(UNKNOWN)
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

  describe ".cached_zen_flex_color_for" do
    it "returns correct color for the period" do
      VCR.use_cassette("zen_flex 2026-01-08 sobriety-eco") do
        time = Time.new(2026, 1, 8, 12, 0, 0, "+01:00")
        expect(EDF.cached_zen_flex_color_for(time)).to eq(RED) # ZENF_PM
        time += 1.day
        expect(EDF.cached_zen_flex_color_for(time)).to eq(RED) # ZENF_PM
        time += 1.day
        expect(EDF.cached_zen_flex_color_for(time)).to eq(BLUE) # RAS
      end
      # entries are cached
      expect($cache.read("zen_flex_color/2026-01-08")).to eq(RED)
      expect($cache.read("zen_flex_color/2026-01-09")).to eq(RED)
      expect($cache.read("zen_flex_color/2026-01-10")).to eq(BLUE)
    end

    it "returns unknown for the future (no cache)" do
      VCR.use_cassette("zen_flex 2030-01-01 unknown") do
        time = Time.new(2030, 1, 1, 12, 0, 0, "+01:00")
        expect(EDF.cached_zen_flex_color_for(time)).to eq(UNKNOWN)
      end
      # entry is NOT cached (never cache UNKNOWN)
      expect($cache.read("zen_flex_color/2030-01-01")).to be_nil
    end

    it "returns GOLD_HP for ZENF_BONIF bonus days" do
      expect(EDF).to receive(:get_json).and_return({'couleurJourJ' => 'ZENF_BONIF'})
      expect(EDF.cached_zen_flex_color_for(Time.new(2026, 3, 1, 12, 0, 0, "+01:00"))).to eq(GOLD_HP)
    end

    it "returns GOLD_HC for ZENF_BONUS bonus days" do
      expect(EDF).to receive(:get_json).and_return({'couleurJourJ' => 'ZENF_BONUS'})
      expect(EDF.cached_zen_flex_color_for(Time.new(2025, 10, 16, 12, 0, 0, "+02:00"))).to eq(GOLD_HC)
    end

    it "returns unknown on errors" do
      expect(EDF).to receive(:get_json).and_return(error: "test")
      expect(EDF.cached_zen_flex_color_for(Time.new(2026, 2, 2, 12))).to eq(UNKNOWN)
    end
  end

  describe ".zen_flex_color_for" do
    it "maps RAS to BLUE" do
      expect(EDF).to receive(:get_json).and_return({'couleurJourJ' => 'RAS'})
      expect(EDF.zen_flex_color_for(Date.new(2026, 1, 10))).to eq(BLUE)
    end

    it "maps ZENF_PM to RED" do
      expect(EDF).to receive(:get_json).and_return({'couleurJourJ' => 'ZENF_PM'})
      expect(EDF.zen_flex_color_for(Date.new(2026, 1, 8))).to eq(RED)
    end

    it "maps ZENF_BONIF to GOLD_HP" do
      expect(EDF).to receive(:get_json).and_return({'couleurJourJ' => 'ZENF_BONIF'})
      expect(EDF.zen_flex_color_for(Date.new(2025, 3, 18))).to eq(GOLD_HP)
    end

    it "maps ZENF_BONUS to GOLD_HC" do
      expect(EDF).to receive(:get_json).and_return({'couleurJourJ' => 'ZENF_BONUS'})
      expect(EDF.zen_flex_color_for(Date.new(2025, 10, 16))).to eq(GOLD_HC)
    end

    it "maps NON_DETERMINE to UNKNOWN" do
      expect(EDF).to receive(:get_json).and_return({'couleurJourJ' => 'NON_DETERMINE'})
      expect(EDF.zen_flex_color_for(Date.new(2030, 1, 1))).to eq(UNKNOWN)
    end

    it "returns unknown on errors" do
      expect(EDF).to receive(:get_json).and_return(error: "test")
      expect(EDF.zen_flex_color_for(Date.today)).to eq(UNKNOWN)
    end
  end
end