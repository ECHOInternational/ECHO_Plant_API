# frozen_string_literal: true

# Mobility 1.x configuration (plugins DSL).
#
# Mobility 0.8 used a global Mobility.configure block with config.default_backend,
# config.accessor_method, config.query_method and config.default_options[...]. In 1.x
# that global config was removed in favour of this per-application plugins DSL, which is
# still evaluated once at boot and applies to every model that calls +translates+.
#
# Each plugin below reproduces exactly the behaviour that was pinned on 0.8.13 by
# spec/models/mobility_compat_spec.rb. Do not add/remove a plugin without re-running that
# spec: a change here can silently alter fallbacks, presence, dirty tracking or the query
# scope and serve wrong-language content while still returning 200.
Mobility.configure do
  plugins do
    # Storage: single jsonb +translations+ column per table, shape {"locale" => {"attr" => v}}.
    # This is the 0.8 config.default_backend = :container. Column name is the Mobility
    # default (+translations+), matching the existing schema.
    backend :container

    # ORM integration (0.8 loaded this implicitly for ActiveRecord models).
    active_record

    # Attribute readers/writers. In 0.8 these were part of the default plugin set that
    # backed +translates :field+ accessors.
    reader
    writer

    # Translation cache, ON by default in 0.8 (config.default_options[:cache] was left at
    # its default). Keeps repeated reads within a request consistent.
    cache

    # Dirty tracking. 0.8 had config.default_options[:dirty] = true. The dirty plugin also
    # pulls in fallthrough_accessors, which is what makes the bare-attr dirty methods
    # (e.g. pests_and_diseases_changed?, _change) work; PaperTrail versioning of translated
    # changes rides on this. fallthrough_accessors is declared explicitly below to make the
    # dependency visible.
    dirty

    # Fallbacks. 0.8 had config.default_options[:fallbacks] = true, which uses I18n.fallbacks
    # (config.i18n.fallbacks = true in application.rb) / I18n.default_locale (:en). A bare
    # +fallbacks+ here reproduces that: a missing locale falls back to the :en value.
    fallbacks

    # Presence. 0.8 shipped presence ON by default (config.default_options[:presence] was
    # never set to false), converting "" to nil on read and write. Declared explicitly to
    # preserve that blank-to-nil semantic (a known 0.8 -> 1.x drift point).
    presence

    # Locale accessors: 0.8 had config.default_options[:locale_accessors] = true. Use the
    # application's available_locales so *_en / *_es style accessors are defined, matching
    # the prior default (true -> Rails available_locales).
    locale_accessors Rails.application.config.i18n.available_locales

    # Fallthrough accessors: enabled implicitly by the dirty plugin in 0.8; declared here so
    # the bare-attr dirty accessors keep working.
    fallthrough_accessors

    # Query scope. 0.8 had config.query_method = :i18n. The bare +query+ plugin defaults the
    # scope name to +i18n+, which is exactly what every collection resolver uses.
    query

    # 0.8 used config.accessor_method = :translates as the DSL entry point. In 1.x
    # +extend Mobility; translates ...+ (already in the models) is the standard entry point,
    # so no accessor_method override is needed.
  end
end
