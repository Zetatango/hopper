# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Hopper::Configuration do
  describe 'load' do
    it 'sets default publish_retry_period' do
      described_class.load({})
      expect(described_class.publish_retry_wait).to eq(1.minute)
    end

    it 'overrides default publish_retry_period' do
      described_class.load(publish_retry_wait: 2.minutes)
      expect(described_class.publish_retry_wait).to eq(2.minutes)
    end

    it 'sets default verify_peer' do
      described_class.load({})
      expect(described_class.verify_peer).to be(false)
    end

    it 'overrides default verify_peer' do
      described_class.load(verify_peer: true)
      expect(described_class.verify_peer).to be(true)
    end

    it 'sets the default uncaught_exception_handler to nil by default' do
      expect(described_class.uncaught_exception_handler).to be_nil
    end

    it 'sets uncaught_exception_handler' do
      handler = proc {}
      described_class.load(uncaught_exception_handler: handler)
      expect(described_class.uncaught_exception_handler).to eq(handler)
    end

    it 'sets consumer_tag to nil by default' do
      described_class.load({})
      expect(described_class.consumer_tag).to be_nil
    end

    it 'sets consumer_tag' do
      described_class.load(consumer_tag: 'web1')
      expect(described_class.consumer_tag).to eq('web1')
    end

    it 'raises NoMethodError for unknown configuration options' do
      expect { described_class.unknown_config }.to raise_error(NoMethodError)
    end
  end

  describe 'respond_to_missing' do
    before do
      described_class.load(test_config: true)
    end

    it 'returns true when the config exists' do
      expect(described_class).to be_respond_to_missing :test_config
    end

    it 'returns false when the config does not exists' do
      expect(described_class).not_to be_respond_to_missing :unknown_config
    end
  end
end
