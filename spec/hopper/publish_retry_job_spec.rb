# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Hopper::PublishRetryJob do
  describe 'perform' do
    let(:message) { 'Hello' }
    let(:message_key) { 'message_key' }

    it 'publishes message' do
      allow(Hopper).to receive(:publish)
      described_class.perform_now(message, message_key)
      expect(Hopper).to have_received(:publish).with(message, message_key)
      ActiveJob::Base.queue_adapter = :test
    end

    it 'retries if the publish raises Bunny::ConnectionClosedError' do
      allow(Hopper).to receive(:publish).and_raise(Bunny::ConnectionClosedError.new(Object.new))
      expect do
        described_class.perform_now(message, message_key)
      end.to have_enqueued_job(described_class)
    end
  end
end
