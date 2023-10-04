# frozen_string_literal: true

require 'rest-client'
require 'token_validator'

class Hopper::ApiRequest
  def execute(method, path, payload = nil)
    RestClient::Request.execute(
      method:,
      url: path,
      headers: { Authorization: "Bearer #{access_token}" },
      payload:
    ) do |response, _request, result|
      raise Hopper::ApiException, "Error response from api #{method}:#{path}: #{result}" unless result.code == '200'

      JSON.parse(response.to_s, symbolize_names: true)
    end
  rescue RestClient::Exception => e
    raise Hopper::HopperRetriableError, "Exception raised while calling api #{method}:#{path}: #{e.message}"
  end

  def access_token
    oauth_token_service = TokenValidator::OauthTokenService.instance
    @api_token = oauth_token_service.access_token[:token]
  end
end
