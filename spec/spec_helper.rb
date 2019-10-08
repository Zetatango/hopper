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

Dir[File.join(Dir.pwd, 'lib', 'hopper.rb')].sort.each { |file| require file }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
