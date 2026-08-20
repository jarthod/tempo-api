require 'app_helper'

RSpec.describe Contract do
  describe "MODES" do
    it "includes tempo, ejp, and zen_flex" do
      expect(Contract::MODES).to eq(%w[tempo ejp zen_flex])
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

    it "sets, reads, and clears manual overrides" do
      expect(Contract.manual_color_for('zen_flex', date)).to be_nil

      Contract.set_manual_override('zen_flex', date, RED)
      expect(Contract.manual_color_for('zen_flex', date)).to eq(RED)
      expect(ManualOverride.find_by(contract: 'zen_flex', date: date).color).to eq(RED)

      # Update override
      Contract.set_manual_override('zen_flex', date, BONUS)
      expect(Contract.manual_color_for('zen_flex', date)).to eq(BONUS)

      # Clear override (Auto / 0)
      Contract.set_manual_override('zen_flex', date, 0)
      expect(Contract.manual_color_for('zen_flex', date)).to be_nil
      expect(ManualOverride.find_by(contract: 'zen_flex', date: date)).to be_nil
    end

    it "prioritizes manual override in .color_for" do
      time = Time.new(2026, 8, 20, 10, 0, 0, "+02:00")
      Contract.set_manual_override('zen_flex', date, BONIF)

      # Should return BONIF without calling EDF API
      expect(EDF).not_to receive(:cached_zen_flex_color_for)
      expect(Contract.color_for('zen_flex', time)).to eq(BONIF)
    end
  end
end
