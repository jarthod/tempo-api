class ManualOverride < ActiveRecord::Base
  validates :contract, presence: true, inclusion: { in: ->(_) { Contract::MODES } }
  validates :date, presence: true
  validates :color, presence: true, numericality: { only_integer: true, greater_than: 0 }
end
