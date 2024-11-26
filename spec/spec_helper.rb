# frozen_string_literal: true

if ENV['COVERAGE'] || ENV['CI']
  require 'simplecov'
  require 'codecov'

  SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new(
    [
      SimpleCov::Formatter::Codecov,
      SimpleCov::Formatter::HTMLFormatter
    ]
  )

  SimpleCov.start do
    add_group 'LIB', %w[lib spec]
  end
end

require 'bundler/setup'
require 'byebug'
require 'webmock/rspec'
require 'bunny-mock'
require 'hopper'
require "action_controller/railtie"
require 'rspec/rails'

Dir[File.join(Dir.pwd, 'lib', 'hopper.rb')].sort.each { |file| require file }

class BugsnagMock
  def notify(_exception)
    puts "BugsnagMock:notify was called"
  end
end

class RedisMock
  def initialize
    @data = {}
  end
  def get(key)
    @data[key]
  end
  def set(key, value, _options = {})
    @data[key] = value
  end
  def del(key)
    @data.delete(key)
  end
  def connected?
    true
  end
  def clear
    @data = {}
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before do
    logger = Logger.new($stdout)
    allow(logger).to receive(:tagged).and_yield
    allow(Rails).to receive(:logger).and_return(logger)
  end
end
