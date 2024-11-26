# frozen_string_literal: true

require 'spec_helper'
require 'redis'

RSpec.describe Hopper do
  let(:queue_name) { 'test_queue' }
  let(:exchange_name) { 'test_exchange' }

  let(:config) do
    {
      url: 'localhost:5672',
      exchange: exchange_name,
      queue: queue_name,
      max_retries: 3
    }
  end

  before do
    described_class.instance_variable_set(:@state, nil)
  end

  after do
    Thread.current[:hopper_connection] = nil
    Thread.current[:hopper_channel] = nil
    described_class.instance_variable_set(:@listening_channel, nil)
  end

  describe '#init_channel' do
    let(:routing_key_a) { 'routing_key1' }
    let(:routing_key_b) { 'routing_key2' }
    let(:connection) { BunnyMock.new }

    before do
      allow(Bunny).to receive(:new).and_return(connection)
    end

    it 'does not throw an exception' do
      expect do
        described_class.init_channel(config)
      end.not_to raise_exception
    end

    it 'initiate connection' do
      described_class.init_channel(config)
      expect(connection).to be_open
    end

    it 'sets the verify_peer option (default options)' do
      described_class.init_channel(config)
      expect(Bunny).to have_received(:new).with(config[:url], hash_including(verify_peer: false))
    end

    it 'sets the verify_peer option' do
      config[:verify_peer] = true
      described_class.init_channel(config)
      expect(Bunny).to have_received(:new).with(config[:url], hash_including(verify_peer: true))
    end

    it 'binds queue to registered routing keys' do
      described_class.init_channel(config)
      described_class.subscribe(Object.new, :dummy_method, [routing_key_a, routing_key_b])

      exchange = described_class.listening_channel.topic(Hopper::Configuration.exchange, durable: true)

      expect(described_class.queue).to be_bound_to(exchange, routing_key: routing_key_a)
      expect(described_class.queue).to be_bound_to(exchange, routing_key: routing_key_b)
    end

    it 'does not initialize channel twice' do
      described_class.instance_variable_set(:@state, Hopper::INITIALIZED)
      allow(connection).to receive(:start)
      described_class.init_channel(config)
      expect(connection).not_to have_received(:start)
    end

    it 'marks the channel as initialized' do
      described_class.init_channel(config)
      expect(described_class.state).to eq(Hopper::INITIALIZED)
    end

    it 'marks the channel as initializing when it fails' do
      allow(connection).to receive(:start).and_raise(Bunny::ConnectionClosedError.new(Object.new))
      expect { described_class.init_channel(config) }.to raise_error(Hopper::HopperInitializationError)
      expect(described_class.state).to eq(Hopper::INITIALIZING)
    end
  end

  describe 'Hopper configuration' do
    let(:bunny_server) { BunnyMock.new }
    let(:connection) { bunny_server.start }
    let(:extra_option_value) { 'value' }

    before do
      allow(Bunny).to receive(:new).and_return(bunny_server)
      allow(bunny_server).to receive(:start).and_return(connection)
      described_class.init_channel(config)
    end

    it 'setups new configured channel' do
      expect(described_class.listening_channel.connection.find_queue(queue_name)).not_to be_nil
    end

    it 'setups new configured exchange' do
      expect(described_class.listening_channel.connection.find_exchange(exchange_name)).not_to be_nil
    end

    it 'initializes hopper configuration' do
      described_class.init_channel(config.merge(extra_option: extra_option_value))
      expect(Hopper::Configuration.extra_option).to eq(extra_option_value)
    end
  end

  describe '#publish' do
    let(:bunny_server) { BunnyMock.new }
    let(:connection) { bunny_server.start }
    let(:channel) { connection.create_channel }
    let(:exchange) { channel.topic(exchange_name) }
    let(:message) { 'Hello' }
    let(:message_key) { 'message_key' }
    let(:message_id) { SecureRandom.uuid }

    before do
      allow(Bunny).to receive(:new).and_return(bunny_server)
      allow(bunny_server).to receive(:start).and_return(connection)
      allow(connection).to receive(:create_channel).and_return(channel)
      allow(channel).to receive(:topic).and_return(exchange)
      allow(exchange).to receive(:publish)
      ActiveJob::Base.queue_adapter = :test
    end

    describe 'when uncaught_exception_handler is set' do
      it 'sets the uncaught_exception_handler' do
        handler = proc { |_error, _component| nil }
        config[:uncaught_exception_handler] = handler

        allow(channel).to receive(:on_uncaught_exception)

        described_class.init_channel(config)

        expect(described_class.listening_channel).to have_received(:on_uncaught_exception).with(no_args) do |*_args, &block|
          expect(handler).to be(block)
        end
      end
    end

    describe 'when not initialized' do
      it 'ignores events' do
        described_class.publish(message, message_key)
        expect(exchange).not_to have_received(:publish)
      end

      it 'logs request' do
        allow(Rails.logger).to receive(:info)
        described_class.publish(message, message_key)
        expect(Rails.logger).to have_received(:info).with("Event #{message_key} not published as Hopper was not initialized in this environment")
      end
    end

    describe 'when initializing' do
      let(:semaphore) { instance_double(Mutex) }

      before do
        allow(described_class).to receive(:semaphore).and_return(semaphore)
        allow(semaphore).to receive(:synchronize).and_yield
        Hopper::Configuration.load(config)
        described_class.instance_variable_set(:@state, Hopper::INITIALIZING)
      end

      describe 'and no other attempt is in progress' do
        before do
          allow(semaphore).to receive(:try_lock).and_return(true)
          allow(semaphore).to receive(:unlock)
        end

        it 'attempts connection' do
          described_class.publish(message, message_key)
          # once called in before
          expect(bunny_server).to have_received(:start).once
        end

        it 'retries publish' do
          described_class.publish(message, message_key)
          expect(Hopper::PublishRetryJob).to have_been_enqueued
        end
      end

      describe 'and another attempt is in progress' do
        before do
          allow(semaphore).to receive(:try_lock).and_return(false)
        end

        it 'does not attempt connection' do
          described_class.publish(message, message_key)
          # once called in before
          expect(bunny_server).not_to have_received(:start)
        end

        it 'retries publish' do
          described_class.publish(message, message_key)
          # once called in before
          expect(Hopper::PublishRetryJob).to have_been_enqueued
        end
      end
    end

    describe 'when initialized' do
      before do
        described_class.init_channel(config)
      end

      it 'publishes the message on the channel' do
        allow(SecureRandom).to receive(:uuid).and_return(message_id)
        described_class.publish(message, message_key)
        expect(exchange).to have_received(:publish).with(message, routing_key: message_key, mandatory: true, persistent: true, message_id:)
      end

      it 'does not trigger the retry job if the publish succeeds' do
        described_class.publish(message, message_key)
        expect(Hopper::PublishRetryJob).not_to have_been_enqueued
      end

      it 'triggers the retry job if the publish raises Bunny::ConnectionClosedError' do
        allow(exchange).to receive(:publish).and_raise(Bunny::ConnectionClosedError.new(Object.new))
        described_class.publish(message, message_key)
        expect(Hopper::PublishRetryJob).to have_been_enqueued
      end

      it 're-queues message if channel does not confirm publish' do
        allow(described_class.channel).to receive(:wait_for_confirms).and_return(false)
        described_class.publish(message, message_key)
        expect(Hopper::PublishRetryJob).to have_been_enqueued
      end

      it 'creates new channel when thread channel is closed' do
        allow(channel).to receive(:closed?).and_return(true, false)
        allow(connection).to receive(:create_channel).and_return(channel)

        described_class.publish(message, message_key)

        # 2 times in setup + 1 for closed channel
        expect(connection).to have_received(:create_channel).at_least(3).times
      end
    end
  end

  describe 'Subscribers' do
    let(:message) do
      {
        object_id: 123
      }
    end

    let(:retriable_error_message) do
      {
        object_id: 234
      }
    end

    let(:non_retriable_error_message) do
      {
        object_id: 456
      }
    end

    let(:routing_key) { 'object.created' }

    let(:redis_mock) do
      instance_double(Redis, get: '0', set: nil, del: nil, connected?: true)
    end

    let(:class_subscriber) do
      Class.new do
        def self.handle_object_created(_event_type, _event, source)
          # evaluate source
          source.class
        end
      end
    end

    let(:instance_subscriber) do
      subscriber_class = Class.new do
        def handle_object_created(_event_type, _event, _source); end
      end
      instance_double(subscriber_class)
    end

    before do
      allow(Redis).to receive(:new).and_return(redis_mock)
      config[:redis] = Redis.new

      allow(Bunny).to receive(:new).and_return(BunnyMock.new)
      described_class.clear
      described_class.init_channel(config)
      described_class.start_listening
    end

    it 'bounds queue to exchange using the routing key' do
      described_class.subscribe(class_subscriber, :handle_object_created, [routing_key])

      expect(described_class.queue).to be_bound_to(described_class.exchange, routing_key:)
    end

    it 'calls subscribers class methods if the topic matches' do
      allow(class_subscriber).to receive(:handle_object_created)
      described_class.subscribe(class_subscriber, :handle_object_created, [routing_key])

      described_class.publish(message.to_json.to_s, routing_key)

      expect(class_subscriber).to have_received(:handle_object_created).with(routing_key, message, nil)
      expect(described_class.queue.message_count).to be_zero
    end

    it 'calls subscribers instance methods if the topic matches' do
      allow(instance_subscriber).to receive(:handle_object_created)
      described_class.subscribe(instance_subscriber, :handle_object_created, [routing_key])

      described_class.publish(message.to_json.to_s, routing_key)

      expect(instance_subscriber).to have_received(:handle_object_created).with(routing_key, message, nil)
      expect(described_class.queue.message_count).to be_zero
    end

    it 'does not call subscribers methods if the topic does not match' do
      allow(class_subscriber).to receive(:handle_object_created).once.and_raise(Hopper::HopperNonRetriableError)
      described_class.subscribe(class_subscriber, :handle_object_created, [routing_key])

      described_class.publish(non_retriable_error_message.to_json.to_s, routing_key)

      expect(described_class.queue.message_count).to be_zero
    end

    it 're-queues message if handling fails with retriable error' do
      allow(class_subscriber).to receive(:handle_object_created).once.and_raise(Hopper::HopperRetriableError)
      allow(class_subscriber).to receive(:handle_object_created).once
      described_class.subscribe(class_subscriber, :handle_object_created, [routing_key])

      described_class.publish(retriable_error_message.to_json.to_s, routing_key)

      expect(described_class.queue.message_count).to be_zero
    end

    it 're-queues message if handling fails with uncaught exception' do
      reponse_values = [:raise, nil]
      allow(class_subscriber).to receive(:handle_object_created).twice do
        rsp = reponse_values.shift
        rsp == :raise ? raise(StandardError) : rsp
      end
      allow(redis_mock).to receive(:get).and_return(1, 2)

      described_class.subscribe(class_subscriber, :handle_object_created, [routing_key])

      described_class.publish(retriable_error_message.to_json.to_s, routing_key)

      expect(described_class.listening_channel.acknowledged_state[:pending].size).to be_zero
      expect(described_class.listening_channel.acknowledged_state[:nacked].size).to eq(1)
      expect(described_class.listening_channel.acknowledged_state[:rejected].size).to be_zero
      expect(described_class.listening_channel.acknowledged_state[:acked].size).to eq(1)
    end

    it 're-queues message if handling fails with uncaught exception too often' do
      allow(class_subscriber).to receive(:handle_object_created).and_raise(StandardError)
      allow(redis_mock).to receive(:get).and_return(1, 2, 3)

      described_class.subscribe(class_subscriber, :handle_object_created, [routing_key])

      described_class.publish(retriable_error_message.to_json.to_s, routing_key)

      expect(described_class.listening_channel.acknowledged_state[:pending].size).to be_zero
      expect(described_class.listening_channel.acknowledged_state[:nacked].size).to eq(2)
      expect(described_class.listening_channel.acknowledged_state[:rejected].size).to eq(1)
      expect(described_class.listening_channel.acknowledged_state[:acked].size).to be_zero
    end

    describe 'will receive source data' do
      let(:source_path) { 'http://localhost:3000/objects/123' }
      let(:object) { { id: 123 } }
      let(:message_with_data) do
        {
          object_id: 123,
          source: source_path
        }
      end
      let(:service) do
        TokenValidator::OauthTokenService.instance
      end

      let(:roadrunner_url) do
        'https://localhost:3002'
      end

      before do
        service.clear
        TokenValidator::ValidatorConfig.configure(
          client_id: '123',
          client_secret: '123',
          requested_scope: '123',
          issuer_url: roadrunner_url,
          audience: 'audience'
        )
        stub_request(:post, "#{roadrunner_url}/oauth/token")
          .to_return(status: 200, body:
            '{"access_token":"abc123","token_type":"bearer",' \
            '"expires_in":7200,"refresh_token":"",' \
            '"scope":"idp:api"}')
        described_class.subscribe(class_subscriber, :handle_object_created, [routing_key])
      end

      it 'as nil if source is not provided' do
        allow(class_subscriber).to receive(:handle_object_created)
        described_class.publish(message.to_json.to_s, routing_key)
        expect(class_subscriber).to have_received(:handle_object_created).with(routing_key, message, nil)
      end

      it 'receives lazy source object and no calls are made if source is not evaluated' do
        allow(class_subscriber).to receive(:handle_object_created)
        described_class.publish(message_with_data.to_json.to_s, routing_key)
        expect(class_subscriber).to have_received(:handle_object_created).with(routing_key, message_with_data, any_args)
      end

      it 'receive real object if evaluated' do
        allow(class_subscriber).to receive(:handle_object_created) { |args| args }
        stub_request(:get, source_path)
          .to_return(status: 200, body: object.to_json.to_s)
        described_class.publish(message_with_data.to_json.to_s, routing_key)
        expect(class_subscriber).to have_received(:handle_object_created).with(routing_key, message_with_data, hash_including(id: 123))
      end

      it 're-queue the message if the get http request fails' do
        stub_request(:get, source_path).to_timeout.times(1).then
                                       .to_return(status: 200, body: object.to_json.to_s)
        described_class.publish(message_with_data.to_json.to_s, routing_key)
        expect(WebMock).to have_requested(:get, source_path).times(2)
      end
    end
  end
end
