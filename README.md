# Hopper

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/hopper`. To experiment with that code, run `bin/console` for an interactive prompt.

TODO: Delete this and the text above, and describe your gem

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'hopper'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install hopper

## Usage

TODO: Write usage instructions here

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

### Ruby

This application requires:

*   Ruby version: 2.7.1

Ruby 2.7.1 and greater requires OpenSSL 1.1+. To link to Homebrew's upgraded version of OpenSSL, add the following to your bash profile

```shell script
export RUBY_CONFIGURE_OPTS="--with-openssl-dir=$(brew --prefix openssl@1.1)"
```

If you do not have Ruby installed, it is recommended you use ruby-install and chruby to manage Ruby versions.

```bash
brew install ruby-install chruby
ruby-install ruby 2.7.1
```

Add the following lines to ~/.bash_profile:

```bash
source /usr/local/opt/chruby/share/chruby/chruby.sh
source /usr/local/opt/chruby/share/chruby/auto.sh
```

Set Ruby version to 2.7.1:

```bash
source ~/.bash_profile
chruby 2.7.1
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/hopper.
