class Device < ActiveRecord::Base
  serialize :settings, coder: JSON
  validates :mode, presence: true, inclusion: { in: ->(_) { Contract::MODES } }
  # created_at & updated_at
end