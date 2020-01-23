# frozen_string_literal: true

require 'active_job'

class Hopper::PublishRetryJob < ActiveJob::Base
  def perform(message, key)
    Rails.logger.error("Retry publish message #{key}:#{message}") if Rails.logger.present?
    Hopper.publish(message, key)
  rescue Bunny::ConnectionClosedError
    Rails.logger.error("Unable to publish message #{key}:#{message}. Retrying in #{Hopper::Configuration.publish_retry_wait}") if Rails.logger.present?
    Hopper::PublishRetryJob.set(wait: Hopper::Configuration.publish_retry_wait).perform_later(message, key)
  end
end
