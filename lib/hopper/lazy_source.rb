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

  # rubocop:disable Style/MethodMissingSuper, Style/MissingRespondToMissing
  def method_missing(method_name, *args, &block)
    __target_object__.send(method_name, *args, &block)
  end
  # rubocop:enable Style/MethodMissingSuper, Style/MissingRespondToMissing
end
