# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Hopper::PublishRetryJob do
  describe 'perform' do
    let(:message) { 'Hello' }
    let(:message_key) { 'message_key' }
    let(:queue_name) { 'test_queue' }
    let(:exchange_name) { 'test_exchange' }

    let(:config) do
      {
        url: 'localhost:5672',
        exchange: exchange_name,
        queue: queue_name
      }
    end

    before do
      Hopper::Configuration.load(config)
      ActiveJob::Base.queue_adapter = :test
    end

    it 'publishes message' do
      allow(Hopper).to receive(:publish)
      described_class.perform_now(message, message_key)
      expect(Hopper).to have_received(:publish).with(message, message_key)
      ActiveJob::Base.queue_adapter = :test
    end

    it 'retries if the publish raises Bunny::ConnectionClosedError' do
      allow(Hopper).to receive(:publish).and_raise(Bunny::ConnectionClosedError.new(Object.new))
      allow(described_class).to receive(:set).and_call_original

      expect do
        described_class.perform_now(message, message_key)
      end.to have_enqueued_job(described_class).with(message, message_key)
    end
  end
end
