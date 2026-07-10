# frozen_string_literal: true

# Rails <= 7.0 + concurrent-ruby >= 1.3.5 boot fix: activesupport references
# Logger::Severity without requiring 'logger'. Remove once Rails >= 7.1.
require 'logger'

ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

require 'bundler/setup' # Set up gems listed in the Gemfile.
require 'bootsnap/setup' # Speed up boot time by caching expensive operations.
