require 'app_helper'

RSpec.describe Contract do
  describe "MODES" do
    it "includes tempo, ejp, zen_flex and hphc" do
      expect(Contract::MODES).to eq(%w[tempo ejp zen_flex hphc])
    end
  end

  describe ".name_for" do
    it "returns human-readable names" do
      expect(Contract.name_for('tempo')).to eq('Tempo')
      expect(Contract.name_for('ejp')).to eq('EJP')
      expect(Contract.name_for('zen_flex')).to eq('Zen Flex')
    end
  end

  describe ".colors_for" do
    it "returns allowed color codes for each contract" do
      expect(Contract.colors_for('tempo')).to eq([BLUE, WHITE, RED])
      expect(Contract.colors_for('ejp')).to eq([GREEN, RED])
      expect(Contract.colors_for('zen_flex')).to eq([ECO, RED, BONIF, BONUS])
    end
  end

  describe ".day_for" do
    it "calculates correct day for tempo (6am boundary)" do
      time_5am = Time.new(2026, 8, 20, 5, 0, 0, "+02:00")
      time_6am = Time.new(2026, 8, 20, 6, 0, 0, "+02:00")
      expect(Contract.day_for('tempo', time_5am)).to eq(Date.new(2026, 8, 19))
      expect(Contract.day_for('tempo', time_6am)).to eq(Date.new(2026, 8, 20))
    end

    it "calculates correct day for ejp" do
      time = Time.new(2026, 2, 7, 1, 0, 0, "+01:00")
      expect(Contract.day_for('ejp', time)).to eq(Date.new(2026, 2, 7))
    end

    it "calculates correct day for zen_flex" do
      time = Time.new(2026, 1, 9, 10, 0, 0, "+01:00")
      expect(Contract.day_for('zen_flex', time)).to eq(Date.new(2026, 1, 9))
    end
  end

  describe "manual overrides" do
    let(:date) { Date.new(2026, 8, 20) }

    it "sets, reads from cache, and clears manual overrides" do
      expect($cache.read("zen_flex_color/#{date}")).to be_nil

      Contract.set_manual_override('zen_flex', date, RED)
      expect($cache.read("zen_flex_color/#{date}")).to eq(RED)

      # Update override
      Contract.set_manual_override('zen_flex', date, BONUS)
      expect($cache.read("zen_flex_color/#{date}")).to eq(BONUS)

      # Clear override (Auto / 0)
      Contract.set_manual_override('zen_flex', date, 0)
      expect($cache.read("zen_flex_color/#{date}")).to be_nil
    end

    it "ignores a color that isn't valid for the given contract" do
      Contract.set_manual_override('zen_flex', date, BLUE) # BLUE is not a zen_flex color
      expect($cache.read("zen_flex_color/#{date}")).to be_nil
    end

    it "returns cached override in .color_for without hitting external API" do
      time = Time.new(2026, 8, 20, 10, 0, 0, "+02:00")
      Contract.set_manual_override('zen_flex', date, BONIF)

      # When cached, EDF.zen_flex_color_for is not called
      expect(EDF).not_to receive(:zen_flex_color_for)
      expect(Contract.color_for('zen_flex', time)).to eq(BONIF)
    end
  end

  describe ".color_for" do
    context "tempo" do
      it "returns and caches the correct color across the 6am boundary" do
        VCR.use_cassette("tempo 2025-02-02 blue-red-white") do
          time = Time.new(2025, 2, 3, 6, 0, 0, "+01:00") # 6am: beginning of tempo RED period
          expect(Contract.color_for('tempo', time-1)).to eq(BLUE)
          expect(Contract.color_for('tempo', time)).to eq(RED)
          time += (22-6).hours # 10pm: end of on-duty hours
          expect(Contract.color_for('tempo', time)).to eq(RED)
          time += 2.hours # 0am: next day but still in the RED period
          expect(Contract.color_for('tempo', time)).to eq(RED)
          time += 6.hours # 6am: beginning next period (WHITE)
          expect(Contract.color_for('tempo', time-1)).to eq(RED)
          expect(Contract.color_for('tempo', time)).to eq(WHITE)
        end
        # entries are cached
        expect($cache.read("tempo_color/2025-02-02")).to eq(BLUE)
        expect($cache.read("tempo_color/2025-02-03")).to eq(RED)
        expect($cache.read("tempo_color/2025-02-04")).to eq(WHITE)
      end

      it "does not cache unknown (future, no data yet)" do
        date = Date.new(2025, 2, 12)
        expect(EDF).to receive(:tempo_color_for).with(date, api: 'api-couleur-tempo.fr').once.and_call_original
        expect(EDF).to receive(:tempo_color_for).with(date, api: 'services-rte.com').once.and_return(UNKNOWN)
        VCR.use_cassette("tempo 2025-02-12 unknown") do
          time = Time.new(2025, 2, 12, 6, 0, 0, "+01:00") # recorded on 2025-03-11
          expect(Contract.color_for('tempo', time)).to eq(UNKNOWN)
        end
        expect($cache.read("tempo_color/2025-02-12")).to be_nil
      end

      it "falls back to second API if needed" do
        expect(EDF).to receive(:tempo_color_for).with(instance_of(Date), api: 'api-couleur-tempo.fr').exactly(3).times.and_return(UNKNOWN)
        expect(EDF).to receive(:tempo_color_for).with(instance_of(Date), api: 'services-rte.com').exactly(3).times.and_call_original
        VCR.use_cassette("tempo RTE 2025-02-22") do
          time = Time.new(2025, 2, 22, 6, 0, 0, "+01:00") # 6am: beginning of tempo RED period
          expect(Contract.color_for('tempo', time-1)).to eq(UNKNOWN)
          expect(Contract.color_for('tempo', time)).to eq(BLUE)
          expect(Contract.color_for('tempo', time+1.day)).to eq(BLUE)
        end
        expect($cache.read("tempo_color/2025-02-21")).to be_nil
        expect($cache.read("tempo_color/2025-02-22")).to eq(BLUE)
        expect($cache.read("tempo_color/2025-02-23")).to eq(BLUE)
      end

      it "returns unknown on errors" do
        expect(EDF).to receive(:get_json).twice.and_return(error: "test") # both API tried
        expect(Contract.color_for('tempo', Time.now)).to eq(UNKNOWN)
      end
    end

    context "ejp" do
      it "returns and caches the correct color across the period boundary" do
        VCR.use_cassette("ejp 2025-02-06 green-red-green") do
          time = Time.new(2025, 2, 7, 0, 0, 0, "+00:00") # 1am Paris (0am London): beginning of EJP RED period
          expect(Contract.color_for('ejp', time-1)).to eq(GREEN)
          expect(Contract.color_for('ejp', time)).to eq(RED)
          time += 23.hours # 0am Paris: next day but still in the RED period
          expect(Contract.color_for('ejp', time)).to eq(RED)
          time += 1.hours # 1am Paris: beginning next period (GREEN)
          expect(Contract.color_for('ejp', time-1)).to eq(RED)
          expect(Contract.color_for('ejp', time)).to eq(GREEN)
        end
        expect($cache.read("ejp_color/2025-02-06")).to eq(GREEN)
        expect($cache.read("ejp_color/2025-02-07")).to eq(RED)
        expect($cache.read("ejp_color/2025-02-08")).to eq(GREEN)
      end

      it "does not cache unknown (future, no data yet)" do
        expect(EDF).to receive(:ejp_color_for).once.and_return(UNKNOWN)
        time = Time.new(2035, 2, 12, 6, 0, 0, "+01:00")
        expect(Contract.color_for('ejp', time)).to eq(UNKNOWN)
        expect($cache.read("ejp_color/2035-02-12")).to be_nil
      end

      it "falls back to green outside of EJP period, without calling the API" do
        expect(EDF).to receive(:ejp_color_for).exactly(2).times.and_return(RED)
        expect(Contract.color_for('ejp', Time.new(2025, 3, 31, 6))).to eq(RED)
        expect(Contract.color_for('ejp', Time.new(2025, 4, 1, 6))).to eq(GREEN) # outside period
        expect(Contract.color_for('ejp', Time.new(2025, 10, 31, 6))).to eq(GREEN) # outside period
        expect(Contract.color_for('ejp', Time.new(2025, 11, 1, 6))).to eq(RED)
        expect($cache.read("ejp_color/2025-03-31")).to eq(RED)
        expect($cache.read("ejp_color/2025-04-01")).to eq(GREEN)
        expect($cache.read("ejp_color/2025-10-31")).to eq(GREEN)
        expect($cache.read("ejp_color/2025-11-01")).to eq(RED)
      end

      it "returns unknown on errors" do
        expect(EDF).to receive(:get_json).and_return(error: "test") # both API tried
        expect(Contract.color_for('ejp', Time.new(2025, 2, 2))).to eq(UNKNOWN)
      end

      it "preserves the current hour for the announce-time gate, not just the target date" do
        VCR.use_cassette("ejp 2025-02-06 green-red-green", record: :none) do
          allow(Date).to receive(:today) { Date.new(2025, 2, 5) }
          before_announce = Time.new(2025, 2, 6, 0, 0, 0, "+00:00") # 1am Paris, before 15:00 announce
          after_announce = before_announce + 15.hours # 3pm Paris, announce time passed
          expect(Contract.color_for('ejp', before_announce)).to eq(UNKNOWN)
          expect(Contract.color_for('ejp', after_announce)).to eq(GREEN)
        end
      end
    end

    context "zen_flex" do
      it "returns and caches the correct color across days" do
        VCR.use_cassette("zen_flex 2026-01-08 sobriety-eco") do
          time = Time.new(2026, 1, 8, 12, 0, 0, "+01:00")
          expect(Contract.color_for('zen_flex', time)).to eq(RED) # ZENF_PM
          time += 1.day
          expect(Contract.color_for('zen_flex', time)).to eq(RED) # ZENF_PM
          time += 1.day
          expect(Contract.color_for('zen_flex', time)).to eq(ECO) # RAS
        end
        expect($cache.read("zen_flex_color/2026-01-08")).to eq(RED)
        expect($cache.read("zen_flex_color/2026-01-09")).to eq(RED)
        expect($cache.read("zen_flex_color/2026-01-10")).to eq(ECO)
      end

      it "does not cache unknown (future, no data yet)" do
        VCR.use_cassette("zen_flex 2030-01-01 unknown") do
          time = Time.new(2030, 1, 1, 12, 0, 0, "+01:00")
          expect(Contract.color_for('zen_flex', time)).to eq(UNKNOWN)
        end
        expect($cache.read("zen_flex_color/2030-01-01")).to be_nil
      end

      it "returns BONIF for ZENF_BONIF bonus days (hitting real data)" do
        VCR.use_cassette("zen_flex 2025-03-18 bonif") do
          expect(Contract.color_for('zen_flex', Time.new(2025, 3, 18, 12, 0, 0, "+01:00"))).to eq(BONIF)
        end
        expect($cache.read("zen_flex_color/2025-03-18")).to eq(BONIF)
      end

      it "returns BONUS for ZENF_BONUS bonus days (hitting real data)" do
        VCR.use_cassette("zen_flex 2025-10-16 bonus") do
          expect(Contract.color_for('zen_flex', Time.new(2025, 10, 16, 12, 0, 0, "+02:00"))).to eq(BONUS)
        end
        expect($cache.read("zen_flex_color/2025-10-16")).to eq(BONUS)
      end

      it "returns unknown on errors" do
        expect(EDF).to receive(:get_json).and_return(error: "test")
        expect(Contract.color_for('zen_flex', Time.new(2026, 2, 2, 12))).to eq(UNKNOWN)
      end
    end
  end
end
