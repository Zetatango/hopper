# frozen_string_literal: true

require 'hopper/version'
require 'hopper/configuration'
require 'hopper/lazy_source'
require 'hopper/jobs/publish_retry_job'
require 'bunny'

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
    attr_reader :state

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
      exchange.publish(message.to_s, options)

      success = channel.wait_for_confirms

      if success
        log(:info, "Sent RabbitMQ message: key=#{key}, id=#{options[:message_id]}")
      else
        log(:error, "Confirmation not received for #{key}:#{message}. Retrying in #{Hopper::Configuration.publish_retry_wait}.")
        Hopper::PublishRetryJob.set(wait: Hopper::Configuration.publish_retry_wait).perform_later(message, key)
      end
    rescue Bunny::Exception => e
      log(:error, "Unable to publish message #{key}:#{message}. Retrying in #{Hopper::Configuration.publish_retry_wait}. Error: #{e.message}")
      Hopper::PublishRetryJob.set(wait: Hopper::Configuration.publish_retry_wait).perform_later(message, key)
    end

    def subscribe(subscriber, method, routing_keys, opts = {})
      routing_keys.each do |routing_key|
        registration = RegistrationStruct.new(subscriber, method, routing_key, opts)
        queue.bind(exchange(listening_channel), routing_key:)
        registrations << registration
      end
    end

    def start_listening
      queue.subscribe(manual_ack: true, block: false, consumer_tag: Hopper::Configuration.consumer_tag) do |delivery_info, properties, body|
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

    def redis
      @redis ||= Hopper::Configuration.configuration[:redis]
    end

    def connection
      thread_local_variable(:hopper_connection) do
        create_connection
      end
    end

    def listening_channel
      @listening_channel ||=
        begin
          ch = create_connection.create_channel
          ch.on_uncaught_exception(&Hopper::Configuration.uncaught_exception_handler) if Hopper::Configuration.uncaught_exception_handler.present?
          ch
        end
    end

    def queue
      @queue ||= listening_channel.queue(Hopper::Configuration.queue, durable: true)
    end

    def channel
      current_channel = thread_local_variable(:hopper_channel) do
        create_channel
      end

      if current_channel.closed?
        log(:warn, "Channel #{current_channel.id} was found to be closed, re-creating")
        current_channel = create_channel
        Thread.current[:hopper_channel] = current_channel
      end

      current_channel
    end

    def exchange(use_channel = channel)
      use_channel.topic(Hopper::Configuration.exchange, durable: true)
    end

    private

    def initialize_hopper
      # call queue just to create the queue if it doesn't exist
      @queue = listening_channel.queue(Hopper::Configuration.queue, durable: true)
      listening_channel.topic(Hopper::Configuration.exchange, durable: true)

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
    rescue StandardError
      # Catch any other type of exception during message handling
      if requeue_poison_message?(routing_key, message)
        log(:info, "Caught unhandled exception while handling message with key #{routing_key}. Requeuing...")
        @listening_channel.nack(delivery_tag, false, true)
      else
        log(:error, "Caught unhandled exception while handling message with key #{routing_key}. Dropping!")
        @listening_channel.reject(delivery_tag, false)
      end
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
        queue.bind(exchange(listening_channel), routing_key: registration.routing_key) unless already_registered.include?(registration.routing_key)
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

    def requeue_poison_message?(routing_key, message)
      return false unless redis.present?
      return false if redis.connected? == false
      return false if message.nil?

      begin
        digest = Digest::SHA256.hexdigest(message.to_s)
        key = "rbmq-retry-cnt-#{routing_key}-#{digest}"
        retry_count = redis.get(key)
        log(:info, "Redis key=#{key}, value=#{retry_count}")
        retry_count = 0 if retry_count.nil?
        retry_count = retry_count.to_i + 1
        if retry_count > Hopper::Configuration.configuration[:max_retries]
          log(:info, "Before del")
          redis.del(key)
          return false
        end
        log(:info, "Before set")
        redis.set(key, retry_count, ex: 30)
      rescue StandardError
        log(:error, "Unable to count the number of rbmq retries.")
        return false
      end
      log(:info, "all done")
      true
    end

    def create_connection
      log(:info, "Creating new connection for #{Thread.current}")
      options = Hopper::Configuration.configuration
      options[:logger] = Rails.logger if Rails.logger.present?

      hopper_connection = Bunny.new Hopper::Configuration.url, options
      hopper_connection.start
      hopper_connection
    end

    def create_channel
      new_channel = connection.create_channel
      new_channel.on_uncaught_exception(&Hopper::Configuration.uncaught_exception_handler) if Hopper::Configuration.uncaught_exception_handler.present?
      new_channel.confirm_select
      log(:info, "Creating new channel #{new_channel.id} for #{Thread.current}")
      new_channel
    end

    def thread_local_variable(var_name, &block)
      result = Thread.current[var_name]
      thread_id = Thread.current.object_id
      log(:info, "Accessing thread var \"#{var_name}\" from thread #{thread_id}, value= #{result}")
      unless result.present?
        result = yield block
        Thread.current[var_name] = result
        log(:info, "Storing thread var \"#{var_name}\" from thread #{thread_id}, value <-- #{result}")
      end

      result
    end
  end
end
# rubocop:enable Metrics/ModuleLength
