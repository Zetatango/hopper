# frozen_string_literal: true

require 'active_support/time'

class Hopper::Configuration
  class << self
    attr_accessor :configuration

    DEFAULTS = {
      publish_retry_wait: 1.minute
    }.freeze

    def load(configuration)
      @configuration = DEFAULTS.merge(configuration)
    end

    def method_missing(method)
      method = method.to_s.sub(/=$/, "").to_sym
      return super unless @configuration.key?(method)

      @configuration[method]
    end

    def respond_to_missing?(method, _include_private = false)
      method = method.to_s.sub(/=$/, "").to_sym
      @configuration.key?(method)
    end
  end
end
