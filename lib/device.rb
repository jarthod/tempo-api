class Device < ActiveRecord::Base
  TIME_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/

  serialize :settings, coder: JSON
  validates :mode, inclusion: { in: Contract::MODES, message: "Veuillez sélectionner un contrat." }
  validate :hc_ranges_must_be_valid
  # created_at & updated_at

  # Temp'Orb sends its ID as raw HEX, but plain digits are read as decimal (legacy IDs)
  def self.parse_id(str)
    str = str.to_s.strip.downcase
    str.match?(/\A[0-9a-f]{12}\z/) && str.match?(/[a-f]/) ? str.to_i(16) : str.to_i
  end

  # Off-peak ranges for the hphc mode: [["22:00", "06:00"], ["12:00", "14:00"]]
  def hc_ranges
    settings&.dig('hc_ranges') || []
  end

  def hc_ranges=(ranges)
    self.settings = (settings || {}).merge('hc_ranges' => ranges)
  end

  private

  def hc_ranges_must_be_valid
    if mode == 'hphc' && hc_ranges.empty?
      errors.add(:base, "Veuillez renseigner vos heures creuses.")
    end
    hc_ranges.each do |range|
      if !range.is_a?(Array) || range.size != 2 || !range.all? { _1.to_s.match?(TIME_FORMAT) }
        errors.add(:base, "Horaire d'heures creuses invalide.")
      elsif range[0] == range[1]
        errors.add(:base, "Les heures de début et de fin doivent être différentes (#{range[0]}).")
      end
    end
  end
end
