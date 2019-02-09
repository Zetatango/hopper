# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Hopper do
  let(:queue_name) { 'test_queue' }
  let(:exchange_name) { 'test_exchange' }

  let(:config) do
    {
      url: 'localhost:5672',
      exchange: exchange_name,
      queue: queue_name
    }
  end

  describe 'Initialize hopper' do
    it 'does not throw an exception' do
      allow(Bunny).to receive(:new).and_return(BunnyMock.new)
      expect do
        described_class.init_channel(config)
      end.not_to raise_exception
    end
  end

  describe 'Hopper configuration' do
    let(:bunny_server) { BunnyMock.new }

    let(:connection) { bunny_server.start }

    before do
      allow(Bunny).to receive(:new).and_return(bunny_server)
      allow(bunny_server).to receive(:start).and_return(connection)
      described_class.init_channel(config)
    end

    it 'setups new configured channel' do
      expect(connection.find_queue(queue_name)).not_to be_nil
    end

    it 'setups new configured exchange' do
      expect(connection.find_exchange(exchange_name)).not_to be_nil
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

    let(:subscriber) do
      Class.new do
        include Hopper::Subscriber

        class << self
          attr_reader :event, :source
        end
        subscribe "object.created", :handle_object_created

        def self.handle_object_created(event, source)
          @event = event
          @source = source
        end
      end
    end

    before do
      allow(Bunny).to receive(:new).and_return(BunnyMock.new)
      described_class.init_channel(config)
      subscriber
      described_class.start_listening
    end

    it 'will bound queue to exchange using the routing key' do
      is_bound = described_class.queue.bound_to?(described_class.exchange, routing_key: routing_key)
      expect(is_bound).to be_truthy
    end

    it 'will call subscribers methods if the topic matches' do
      described_class.publish(message.to_json.to_s, routing_key)
      expect(subscriber.event).to eq(message)
      expect(described_class.queue.message_count).to be_zero
    end

    it 'will not call subscribers methods if the topic does not match' do
      allow(subscriber).to receive(:handle_object_created).once.and_raise(Hopper::HopperNonRetriableError)
      described_class.publish(non_retriable_error_message.to_json.to_s, routing_key)
      expect(described_class.queue.message_count).to be_zero
    end

    it 'will re-queue message if handling fails with retriable error' do
      allow(subscriber).to receive(:handle_object_created).once.and_raise(Hopper::HopperRetriableError)
      allow(subscriber).to receive(:handle_object_created).once
      described_class.publish(retriable_error_message.to_json.to_s, routing_key)
      expect(described_class.queue.message_count).to be_zero
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

      let(:zetatango_url) do
        'https://localhost:3000'
      end

      before do
        service.clear
        TokenValidator::ValidatorConfig.configure(roadrunner_url: roadrunner_url, zetatango_url: zetatango_url)
        stub_request(:post, "#{roadrunner_url}/oauth/token")
          .to_return(status: 200, body:
            '{"access_token":"abc123","token_type":"bearer",' \
            '"expires_in":7200,"refresh_token":"",' \
            '"scope":"idp:api"}')
      end

      it 'as nil if source is not provided' do
        described_class.publish(message.to_json.to_s, routing_key)
        expect(subscriber.source).to be_nil
      end

      it 'receive source object' do
        stub_request(:get, source_path)
          .to_return(status: 200, body: object.to_json.to_s)
        described_class.publish(message_with_data.to_json.to_s, routing_key)
        expect(subscriber.source).to eq(object)
      end

      it 're-queue the message if the get fails' do
        stub_request(:get, source_path).to_timeout.times(1).then
                                       .to_return(status: 200, body: object.to_json.to_s)
        described_class.publish(message_with_data.to_json.to_s, routing_key)
        expect(subscriber.source).to eq(object)
      end
    end
  end
end
