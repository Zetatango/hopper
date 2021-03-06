# frozen_string_literal: true

require 'hopper/api_request'

class LazySource < ::BasicObject
  def initialize(source)
    @__source__ = source
  end

  def __target_object__
    @__target_object__ ||= ::Hopper::ApiRequest.new.execute('GET', @__source__)
    @__target_object__
  end

  # rubocop disable is needed as the class is extending BasicObject (no respond_to_missing?, should not respond to super)
  # rubocop:disable Style/MissingRespondToMissing
  def method_missing(method_name, *args, &block)
    __target_object__.send(method_name, *args, &block)
  end
  # rubocop:enable Style/MissingRespondToMissing
end
