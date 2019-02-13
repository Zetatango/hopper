# frozen_string_literal: true

module Hopper::Subscriber
  def self.included(base)
    base.send :include, InstanceMethods
    base.extend ClassMethods
  end

  module InstanceMethods; end

  module ClassMethods
    def subscribe(routing_key, method)
      subscriber = Hopper::SubscriberStruct.new(self, method, routing_key)
      Hopper.add_subscriber(subscriber)
    end
  end
end
