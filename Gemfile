# frozen_string_literal: true

ruby '>= 3.3.0'

source "https://rubygems.org"

git_source(:github) do |repo_name|
  repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?('/')
  "https://github.com/#{repo_name}.git"
end

gemspec

gem 'token_validator', github: 'Zetatango/token_validator', tag: 'v0.7.0'
