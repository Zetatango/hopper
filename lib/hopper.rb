# frozen_string_literal: true

require 'hopper/version'
require 'hopper/configuration'
require 'hopper/lazy_source'
require 'hopper/jobs/publish_retry_job'
require 'bunny'
require 'connection_pool'

# rubocop:disable Metrics/ModuleLength
module Hopper
  # rubocop:disable Lint/StructNewOverride
  RegistrationStruct = Struct.new(:subscriber, :method, :routing_key, :opts)
  # rubocop:enable Lint/StructNewOverride

  class HopperError < StandardError; end

  class ApiException < HopperError; end
  class InvalidMessageError < HopperError; end
  class HopperRetriableError < HopperError; end
  class HopperNonRetriableError < HopperError; end

  class HopperInitializationError < HopperError
    attr_reader :original_exception

    def initialize(exception)
      super
      @original_exception = exception
    end
  end

  NOT_CONFIGURED = "not_configured"
  INITIALIZING = "initializing"
  INITIALIZED = "initialized"

  class << self
    attr_reader :listening_channel, :queue, :state, :connection

    def init_channel(config)
      Hopper::Configuration.load(config)
      # lock semaphore to stop publishing while initializing
      semaphore.synchronize do
        # this should never happen
        return if initialized?

        @state = INITIALIZING
        initialize_hopper
      end
    rescue Bunny::Exception => e
      log(:error, "Unable to connect to RabbitMQ: #{e.message}")
      raise HopperInitializationError, e
    end

    def publish(message, key)
      if not_configured?
        log(:info, "Event #{key} not published as Hopper was not initialized in this environment")
        return
      end

      if initializing?
        log(:info, "Event #{key} not published as Hopper was still initializing in this environment")
        initialize_hopper_attempt
        # this may or may not succeed on initializing channel so we have to retry
        Hopper::PublishRetryJob.set(wait: Hopper::Configuration.publish_retry_wait).perform_later(message, key)
        log(:info, "Event #{key} was queued for publishing")
        return
      end

      message = message.to_json if message.is_a? Hash
      options = message_options(key)

      @pool.with do |channel|
        exchange = channel.topic(Hopper::Configuration.exchange, durable: true)
        exchange.publish(message.to_s, options)
        success = channel.wait_for_confirms

        if success
          log(:info, "Sent RabbitMQ message: key=#{key}, id=#{options[:message_id]}")
        else
          log(:error, "Confirmation not received for #{key}:#{message}. Retrying in #{Hopper::Configuration.publish_retry_wait}.")
          Hopper::PublishRetryJob.set(wait: Hopper::Configuration.publish_retry_wait).perform_later(message, key)
        end
      end
    rescue Bunny::Exception => e
      log(:error, "Unable to publish message #{key}:#{message}. Retrying in #{Hopper::Configuration.publish_retry_wait}. Error: #{e.message}")
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
      @queue.subscribe(manual_ack: true, block: false, consumer_tag: Hopper::Configuration.consumer_tag) do |delivery_info, properties, body|
        log(:info,
            "Received RabbitMQ message: key=#{delivery_info.routing_key}, id=#{properties[:message_id]}. tag=#{delivery_info.delivery_tag}")
        with_log_tagging(properties[:message_id]) do
          handle_message(delivery_info.delivery_tag, delivery_info.routing_key, body)
        end
      end
    end

    def clear
      @registrations = []
    end

    def semaphore
      @semaphore ||= Mutex.new
    end

    private

    def initialize_hopper
      options = Hopper::Configuration.configuration
      options[:logger] = Rails.logger if Rails.logger.present?

      connection = Bunny.new Hopper::Configuration.url, options
      connection.start

      @pool ||= ConnectionPool.new do
        channel = connection.create_channel
        channel.on_uncaught_exception(&Hopper::Configuration.uncaught_exception_handler) if Hopper::Configuration.uncaught_exception_handler.present?
        channel.confirm_select
        channel
      end

      @listening_channel = @pool.checkout
      @listening_channel.on_uncaught_exception(&Hopper::Configuration.uncaught_exception_handler) if Hopper::Configuration.uncaught_exception_handler.present?
      @listening_channel.topic(Hopper::Configuration.exchange, durable: true)
      @queue = @listening_channel.queue(Hopper::Configuration.queue, durable: true)

      bind_subscribers
      @state = INITIALIZED
    end

    def initialize_hopper_attempt
      return unless semaphore.try_lock && !initialized?

      begin
        initialize_hopper
      ensure
        semaphore.unlock
      end
    end

    def handle_message(delivery_tag, routing_key, message)
      message_data = JSON.parse(message, symbolize_names: true)
      source_object = LazySource.new(message_data[:source]) unless message_data[:source].nil?
      registrations.each do |registration|
        next unless registration.routing_key == routing_key

        log(:info, "Sending #{routing_key} message to #{registration.subscriber}:#{registration.method}")
        registration.subscriber.send(registration.method, routing_key, message_data, source_object)
      end

      log(:info, "Acknowledging #{delivery_tag}.")

      @listening_channel.acknowledge(delivery_tag, false)
    rescue HopperRetriableError
      log(:warn, "Rejecting #{delivery_tag} due to retriable error")

      # it means it's a temporary error and the error needs to be re-sent
      @listening_channel.reject(delivery_tag, true)
    rescue HopperNonRetriableError
      log(:error, "Acknowledging #{delivery_tag} due to non-retriable error")

      # this means the message should not be delivered again
      # maybe added to a different queue for manual processing?
      @listening_channel.acknowledge(delivery_tag, false)
    end

    def message_options(key)
      {
        routing_key: key,
        mandatory: true,
        persistent: true,
        message_id: SecureRandom.uuid
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

    def not_configured?
      @state.blank?
    end

    def initializing?
      @state == INITIALIZING
    end

    def initialized?
      @state == INITIALIZED
    end

    def log(level, message)
      Rails.logger.send(level, message) if Rails.logger.present?
    end

    def with_log_tagging(message_id, &block)
      yield block unless Rails.logger.present?

      Rails.logger.tagged(message_id) do
        yield block
      end
    end
  end
end
# rubocop:enable Metrics/ModuleLength
