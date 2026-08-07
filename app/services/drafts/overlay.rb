# frozen_string_literal: true

module Drafts
  # Applies a draft's staged values onto a loaded record IN MEMORY. The record
  # is never saved: the caller hands the dirty instance straight to graphql-ruby
  # for serialization, exactly as ChangeHistory::Restorer hands back a reified
  # version.
  #
  # The whitelist is re-applied here even though the write path already filters,
  # so a draft row written by an older version of the code (or by hand) cannot
  # overlay a column it was never allowed to stage.
  module Overlay
    TRANSLATIONS = 'translations'

    module_function

    def apply(record, draft)
      return record if draft.nil?

      staged = draft.data.slice(*DraftableAttributes.for(record.class))

      staged.each do |attribute, value|
        next if attribute == TRANSLATIONS

        record.public_send("#{attribute}=", value)
      end

      overlay_translations(record, staged[TRANSLATIONS]) if staged.key?(TRANSLATIONS)
      record
    end

    # The Mobility container column needs more care than a plain attribute.
    #
    # Assignment itself does round-trip: the column is declared with
    # `store :translations, coder: Container::Coder`, whose IndifferentCoder
    # casts whatever is assigned into a HashWithIndifferentAccess, so the
    # backend's `model[column_name][locale]` lookup finds a staged locale
    # whether the draft blob arrived with string or symbol keys. Three things
    # still have to be handled by hand.
    #
    # 1. MERGE, NOT REPLACE. A draft stages only the locales an editor touched.
    #    Assigning that blob wholesale would drop every other locale from the
    #    in-memory record, so a Swahili draft would blank the live English
    #    content in the response (and, once Drafts publishes, on disk). The
    #    merge is deep so a draft that stages only `sw.description` leaves a
    #    live `sw.pests_and_diseases` alone. An explicitly staged nil still
    #    wins over the live value, which is how a draft clears a translation.
    #
    # 2. DROP THE READ CACHE. Mobility's cache plugin memoises one value per
    #    locale on the backend instance, and only reload / changes_applied /
    #    clear_changes_information drop it. Any read that happened before the
    #    overlay -- a policy check, an earlier field resolver, the conflict
    #    detector -- would otherwise pin the pre-draft value for the rest of
    #    the request, because the cache is consulted before the container is.
    #    Clearing is safe: it touches no ActiveRecord dirty state, so the
    #    record stays `changed?` and stays unsaved.
    #
    # 3. KEEP THE CONTAINER SAVABLE. See keep_container_savable below. This
    #    overlay does not save, but Drafts' publisher saves what it overlays,
    #    and one reachable draft leaves a record that cannot be saved at all.
    def overlay_translations(record, staged)
      # A hand-written or older-format draft row, at either level: the blob
      # itself, or one locale inside it. Serialization must not die on it.
      return unless staged.is_a?(Hash)

      usable = staged.select { |_locale, values| values.is_a?(Hash) }
      return if usable.empty?

      record.translations = (record.translations || {}).deep_merge(usable)
      keep_container_savable(record, usable.keys)
      drop_mobility_cache(record)
    end

    # `translations` is `jsonb NOT NULL`, and Rails' Type::Serialized returns
    # nil from #serialize for any value equal to `coder.load(nil)` -- an empty
    # hash -- so a record whose container is exactly `{}` is written as SQL
    # NULL and rejected by the constraint.
    #
    # The value to test is the one AFTER assignment, not the hash handed to the
    # writer. Type::Serialized inherits the json subtype's mutable-value `cast`
    # (`deserialize(serialize(value))`), so assignment round-trips through
    # Container::Coder#dump, which strips every blank leaf and then every
    # emptied locale. A draft that clears the last surviving translated field
    # of the last surviving locale therefore assigns
    # `{"en" => {"description" => nil}}` and leaves `{}` sitting on the record:
    # in-memory reads are correct, and the next `save!` raises
    # ActiveRecord::NotNullViolation. That is an ordinary publisher call
    # pattern, not a hypothetical.
    #
    # Re-seeding the staged locales with empty hashes is exactly what the
    # backend's own reader does (`model[column_name][locale] ||= {}`), and it
    # is enough: `{"en" => {}}` is not equal to the sentinel, so it dumps to
    # `{}` and persists as the empty container the column defaults to. The
    # clear is honoured rather than silently dropped -- unlike
    # ChangeHistory::Restorer, which resolves the same type-level trap by
    # skipping the column and accepting a partial restore. It must be an
    # in-place mutation: re-assigning would cast, strip and empty it again.
    def keep_container_savable(record, locales)
      return unless record.translations.empty?

      locales.each { |locale| record.translations[locale.to_s] ||= {} }
    end

    def drop_mobility_cache(record)
      return unless record.respond_to?(:mobility_backends)

      # Lazily built and memoised per attribute, so this iterates exactly the
      # backends something has already read through.
      record.mobility_backends.each_value do |backend|
        backend.clear_cache if backend.respond_to?(:clear_cache)
      end
    end
  end
end
