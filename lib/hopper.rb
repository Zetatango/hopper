# frozen_string_literal: true

require 'hopper/version'
require 'hopper/configuration'
require 'hopper/lazy_source'
require 'hopper/jobs/publish_retry_job'
require 'bunny'

module Hopper
  RegistrationStruct = Struct.new(:subscriber, :method, :routing_key, :opts)

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
      bind_subscribers
      Hopper::Configuration.load(config)
      @configured = true
    end

    def publish(message, key)
      unless @configured
        Rails.logger.info("Event #{key} not published as Hopper was not initialized in this environment")
        return
      end

      message = message.to_json if message.is_a? Hash
      options = message_options(key)
      @exchange.publish(message.to_s, options)
    rescue Bunny::ConnectionClosedError
      Rails.logger.error("Unable to publish message #{key}:#{message}. Retrying in #{Hopper::Configuration.publish_retry_wait}") if Rails.logger.present?
      Hopper::PublishRetryJob.set(wait: Hopper::Configuration.publish_retry_wait).perform_later(message, key)
    end

    def subscribe(subscriber, method, routing_keys, opts = {})
      routing_keys.each do |routing_key|
        registration = RegistrationStruct.new(subscriber, method, routing_key, opts)
        @queue.bind(@exchange, routing_key: routing_key) if @queue.present?
        registrations << registration
      end
    end

    def start_listening
      @queue.subscribe(manual_ack: true, block: false) do |delivery_info, _properties, body|
        handle_message(delivery_info.delivery_tag, delivery_info.routing_key, body)
      end
    end

    def clear
      @registrations = []
    end

    private

    def handle_message(delivery_tag, routing_key, message)
      message_data = JSON.parse(message, symbolize_names: true)
      source_object = LazySource.new(message_data[:source]) unless message_data[:source].nil?
      registrations.each do |registration|
        registration.subscriber.send(registration.method, routing_key, message_data, source_object) if registration.routing_key == routing_key
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

    def bind_subscribers
      already_registered = Set.new
      registrations.each do |registration|
        @queue.bind(@exchange, routing_key: registration.routing_key) unless already_registered.include?(registration.routing_key)
        already_registered << registration.routing_key
      end
    end

    def registrations
      @registrations ||= []
    end
  end
end
