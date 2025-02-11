class Device < ActiveRecord::Base
  serialize :settings, coder: JSON
  validates :mode, presence: true, inclusion: { in: %w(tempo ejp) }
end