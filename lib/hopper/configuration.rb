# frozen_string_literal: true

require 'active_support'
require 'active_support/time'

class Hopper::Configuration
  class << self
    attr_accessor :configuration

    DEFAULTS = {
      publish_retry_wait: 1.minute,
      verify_peer: false,
      uncaught_exception_handler: nil,
      consumer_tag: nil,
      max_retries: 3,
      redis: nil,
      bugsnag: nil
    }.freeze

    def load(configuration)
      @configuration = DEFAULTS.merge(configuration)
    end

    def method_missing(method)
      return super unless @configuration.key?(method.to_sym)

      @configuration[method.to_sym]
    end

    def respond_to_missing?(method, _include_private = false)
      @configuration.key?(method.to_sym)
    end
  end
end
