# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '~> 3.3.0'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '~> 7.2.3'
# Use postgresql as the database for Active Record
gem 'pg', '~> 1.6.3'
# Use Puma as the app server
gem 'puma', '~> 6.6'
# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
# gem 'jbuilder', '~> 2.7'
# Use Redis adapter to run Action Cable in production
# gem 'redis', '~> 4.0'
# Use Active Model has_secure_password
# gem 'bcrypt', '~> 3.1.7'

# Use Active Storage variant
# gem 'image_processing', '~> 1.2'

# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', '>= 1.10', require: false

# Authentication
gem 'jwt', '~> 2.10'

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin AJAX possible
gem 'rack-cors', '~> 2.0.2'

# Accept-Language Header
gem 'http_accept_language'

# Features
# Versioning
gem 'paper_trail', '~> 16.0'
# I18n
# Held at 1.2.9: mobility 1.3.x has a container-backend regression (Container#write
# returns the decorated read; the cache+dirty plugin chain then poisons in-memory
# reads of just-written translations with nil, breaking create for translated-only
# records). Bump when a fixed release (> 1.3.2) passes
# spec/models/mobility_compat_spec.rb unchanged.
gem 'mobility', '~> 1.2.9'
# Graphql
gem 'graphql', '~> 2.3.23'
gem 'search_object_graphql', '~> 1.0.5'
# Authorization Policies
gem 'pundit', '~> 2.5'

# S3 presigned URL generation for direct image uploads
gem 'aws-sdk-s3', '~> 1'

# Health Checks
gem 'rails-healthcheck'

group :development, :test do
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  gem 'byebug', platforms: %i[mri mingw x64_mingw]
  gem 'factory_bot_rails', '~> 6.4'
  gem 'faker', '~> 3.5'
  gem 'pundit-matchers'
  gem 'rspec-rails', '~> 8.0'
end

group :development do
  # Rails 7.0 EventedFileUpdateChecker requires listen ~> 3.5; keep listen (dev file watcher).
  gem 'listen', '~> 3.5'
  gem 'rubocop', require: false
end

group :test do
  gem 'simplecov', require: false
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]
