# frozen_string_literal: true

require "hopper/version"

module Hopper
  class << self
    include Singleton

    class ConfigurationError < RuntimeError; end
    class ApiException < StandardError; end

    SubscriberStruct = Struct.new(:class, :method, :routing_key)

    def init_channel(config)
      raise ConfigurationError, "Hopper was already configured" if @configured

      connection = Bunny.new config[:url]
      connection.start
      @channel = connection.create_channel
      @exchange = @channel.headers(config[:exchange], durable: true)
      @queue = @channel.queue(config[:queue], durable: true)
      @subscribers = []
      @configured = true
    end

    def publish(message, key)
      @exchange.publish(message, message_options(key))
    end

    def add_subscriber(subscriber)
      @queue.bind(@exchange, routing_key: subscriber.routing_key)
      @subscribers << subscriber
    end

    private

    def start_listening
      @queue.subscribe(block: true) do |_delivery_info, _properties, body|
        handle_message("something", body)
      end
    end

    def handle_message(routing_key, message)
      source = Hopper::APIRequest.new()
      subscribers.each do |subscriber|
        subscriber.handle_message(message) if subscriber.routing_key == message
      end
    end

    def message_options(key)
      {
        routing_key: key,
        mandatory: true,
        persistent: true
      }
    end
  end
end
