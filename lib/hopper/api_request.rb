
# frozen_string_literal: true

module Hopper::ApiRequest
  def initialize(method, path, payload = nil)
    @method = method
    @payload = payload
    @path = path
  end

  private

  def execute
    RestClient::Request.execute(
      method: @method,
      url: @path,
      headers: { Authorization: "Bearer #{access_token}" },
      payload: @payload
    ) do |response, _request, result|
      raise Hopper::ApiException, "Error response from api #{@method}:#{@path}: #{result}" unless result.code == '200'
      JSON.parse(response.to_s)
    end
  rescue StandardError => e
    raise Hopper::ApiException, "Exception raised while calling api #{@method}:#{@path}: #{e.message}"
  end

  def access_token
    oauth_token_service = "TokenValidator::OauthTokenService".constantize.instance
    @api_token = oauth_token_service.access_token[:token]
  end
end
