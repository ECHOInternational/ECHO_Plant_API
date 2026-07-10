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
    config.load_defaults 7.2

    # Rails 7.0 defaults partial_inserts to false, which forces every column
    # (including the Mobility container backend jsonb translations column) into
    # the INSERT. Mobility 1.2.9 leaves translations as nil in memory for a
    # record with no translated attributes set and relies on the column's
    # DB-side DEFAULT '{}'. With full inserts that nil is sent explicitly and
    # violates the NOT NULL constraint, so partial_inserts is pinned to true.
    # The documented relax condition (the next Mobility bump) arrived at the
    # Rails 7.2 rung and was BLOCKED: mobility 1.3.x has a container-backend
    # regression (Container#write returns the decorated read; the cache+dirty
    # plugin chain then poisons in-memory reads of just-written translations
    # with nil), so mobility stays held at 1.2.9. Unpin when a fixed mobility
    # (> 1.3.2) passes the 9-example spec/models/mobility_compat_spec.rb
    # unchanged.
    config.active_record.partial_inserts = true

    # app/models/life_cycle_events is an explicit autoload root (STI subtree:
    # LifeCycleEvent + 22 subclasses). Because it is declared as its own root it
    # is NOT covered by app/models' default eager load, so in production it was
    # skipped by eager loading (0/22 files required; zeitwerk:check flagged it).
    # Add it to eager_load_paths so every STI subclass is loaded at boot
    # (eager_load_paths entries are autoloaded too, so this also preserves dev/
    # test autoloading). lib stays autoload-only: its two files (cors_origins,
    # paper_trail_yaml_serializer) are require'd explicitly by their initializers
    # and eager-loading lib is discouraged.
    config.eager_load_paths << "#{config.root}/app/models/life_cycle_events"
    config.autoload_paths << "#{config.root}/lib"

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
