# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LazySource do
  let(:source_url) { 'http://localhost/123' }
  let(:object) { { id: 123 } }
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
  end

  describe 'Lazy source' do
    it 'will call source url to obtain the object' do
      stub_request(:get, source_url)
        .to_return(status: 200, body: object.to_json.to_s)
      expect(described_class.new(source_url)).to be_a(Hash)
    end

    it 'will delegate respond_to? to target object' do
      stub_request(:get, source_url)
        .to_return(status: 200, body: object.to_json.to_s)
      expect(described_class.new(source_url)).to respond_to(:keys)
    end

    it 'will not initiate request if not evaluated' do
      _source = described_class.new(source_url)
      expect(WebMock).to have_requested(:get, source_url).times(0)
    end
  end
end
