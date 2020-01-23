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
