# frozen_string_literal: true

ruby '2.5.3'

source "https://rubygems.org"

git_source(:github) do |repo_name|
  repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?('/')
  "https://github.com/#{repo_name}.git"
end

gemspec

group :test, :development do
  gem 'bunny-mock', git: 'https://github.com/arempe93/bunny-mock'
  gem 'token_validator', github: 'Zetatango/token_validator'
end
