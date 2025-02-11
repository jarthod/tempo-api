ENV['RACK_ENV'] = 'test'
require 'rspec'
require 'rack/test'
require './tempo-api'
require 'active_support/testing/time_helpers'
require 'capybara'
require 'capybara/rspec'

RSpec.configure do |config|
  config.include Capybara::DSL, :request
  config.include Rack::Test::Methods
  config.include ActiveSupport::Testing::TimeHelpers

  def app = Sinatra::Application
  app.logger.level = Logger::WARN

  config.before(:suite) do
    ActiveRecord::Migration.verbose = false
    load "./db/schema.rb"
  end

  config.after(:each) do
    ActiveRecord::Base.connection.tables.each do |table|
      next if table == "schema_migrations" # Don't delete migration records
      ActiveRecord::Base.connection.execute("DELETE FROM #{table};")
    end
  end
end

require 'vcr'
VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr"
  config.hook_into :webmock
end

Capybara.app = Sinatra::Application
