# frozen_string_literal: true

require_relative 'boot'

require 'rails'
# Pick the frameworks you want:
require 'active_model/railtie'
require 'active_job/railtie'
require 'active_record/railtie'
require 'active_storage/engine'
require 'action_controller/railtie'
require 'action_mailer/railtie'
require 'action_mailbox/engine'
require 'action_text/engine'
require 'action_view/railtie'
require 'action_cable/engine'
# require "sprockets/railtie"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module API
  # Defines configuration for the entire Rails Application
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.1

    # Rails 7.0 defaults partial_inserts to false, which forces every column
    # (including the Mobility container backend jsonb translations column) into
    # the INSERT. Mobility 1.2.9 (frozen on this ladder rung) leaves translations
    # as nil in memory for a record with no translated attributes set and relies
    # on the column's DB-side DEFAULT '{}'. With full inserts that nil is sent
    # explicitly and violates the NOT NULL constraint. Pin partial_inserts back
    # to true until Mobility is upgraded to seed the attribute default itself.
    config.active_record.partial_inserts = true

    config.autoload_paths += %W[#{config.root}/app/models/life_cycle_events #{config.root}/lib]

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true
    config.i18n.fallbacks = true
    config.i18n.available_locales = %i[en es fr th zh km id vi my sw hi ht sv pt de am ne bi rw ko so ber bn]
    config.i18n.default_locale = :en
  end
end
