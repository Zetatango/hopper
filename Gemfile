# frozen_string_literal: true

ruby '2.7.0'

source "https://rubygems.org"

git_source(:github) do |repo_name|
  repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?('/')
  "https://github.com/#{repo_name}.git"
end

gemspec

gem 'token_validator', github: 'Zetatango/token_validator'
