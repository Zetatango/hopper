# frozen_string_literal: true

require 'hopper/version'
require 'hopper/subscriber'
require 'hopper/api_request'
require 'bunny'

module Hopper
  SubscriberStruct = Struct.new(:class, :method, :routing_key)

  class ConfigurationError < RuntimeError; end
  class ApiException < StandardError; end
  class InvalidMessageError < StandardError; end
  class HopperRetriableError < StandardError; end
  class HopperNonRetriableError < StandardError; end

  class << self
    attr_reader :channel, :queue, :exchange

    def init_channel(config)
      connection = Bunny.new config[:url]
      connection.start
      @channel = connection.create_channel
      @exchange = @channel.topic(config[:exchange], durable: true)
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

    def start_listening
      @queue.subscribe(manual_ack: true, block: false) do |delivery_info, _properties, body|
        handle_message(delivery_info.delivery_tag, delivery_info.routing_key, body)
      end
    end

    private

    def handle_message(delivery_tag, routing_key, message)
      message_data = JSON.parse(message, symbolize_names: true)
      source_object = Hopper::ApiRequest.instance.execute('GET', message_data[:source]) unless message_data[:source].nil?
      @subscribers.each do |subscriber|
        subscriber.class.send(subscriber.method, message_data, source_object) if subscriber.routing_key == routing_key
      end
      @channel.acknowledge(delivery_tag, false)
    rescue HopperRetriableError
      # it means it's a temporary error and the error needs to be re-sent
      @channel.reject(delivery_tag, true)
    rescue HopperNonRetriableError
      # this means the message should not be delivered again
      # maybe added to a different queue for manual processing?
      @channel.acknowledge(delivery_tag, false)
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
