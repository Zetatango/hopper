# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'hopper/version'

Gem::Specification.new do |spec|
  spec.name          = 'hopper'
  spec.version       = Hopper::VERSION
  spec.authors       = ['Dragos Bobes']
  spec.email         = ['dragos.bobes@zetatango.com']

  spec.summary       = 'A library that handles event messaging needs for zt services'
  spec.homepage      = 'https://github.com/Zetatango/hopper'

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise 'RubyGems 2.0 or newer is required to protect against ' \
      'public gem pushes.'
  end

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler-audit'
  spec.add_development_dependency 'codecov'
  spec.add_development_dependency 'rspec-collection_matchers'
  spec.add_development_dependency 'rspec-mocks'
  spec.add_development_dependency 'rspec_junit_formatter'
  spec.add_development_dependency 'rubocop'
  spec.add_development_dependency 'rubocop-rspec'
  spec.add_development_dependency 'rubocop_runner', '~> 2.0'
  spec.add_development_dependency 'simplecov'
  spec.add_development_dependency 'timecop'

  spec.add_dependency 'bunny', '>= 2.13.0'
  spec.add_dependency 'rest-client'
end
