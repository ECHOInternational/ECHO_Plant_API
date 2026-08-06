# frozen_string_literal: true

module ChangeHistory
  # Turns a version's object_changes into the field-level diff the API renders.
  #
  # Column names become the camelCase graphql field names, values are humanized
  # (ranges as postgres literals, enums as their graphql names, booleans as
  # true/false), and the Mobility container column is flattened into one entry
  # per locale and attribute.
  #
  # Ownership and visibility changes are deliberately KEPT: they are meaningful
  # audit events. The dual-write mirrors of visibility (publication_state,
  # access_level, deleted_at, deleted_by_principal_id) are skipped instead,
  # because reporting the same transition three times is noise.
  class DiffBuilder
    SKIPPED_COLUMNS = %w[
      id created_at updated_at translations
      plant_id variety_id imageable_id imageable_type
      category_id tolerance_id growth_habit_id antinutrient_id
      publication_state access_level deleted_at deleted_by_principal_id
      data_source_id source_record_id source_updated_at last_synced_at
      source_digest sync_state source_snapshot
    ].freeze

    # Frozen legacy contract, mirrored here so the builder never has to
    # constantize an item_type to read an enum.
    VISIBILITY_NAMES = { 0 => 'PRIVATE', 1 => 'PUBLIC', 2 => 'DRAFT', 3 => 'DELETED' }.freeze

    ENUM_COLUMNS = %w[early_growth_phase life_cycle].freeze

    # Ownership columns kept in diffs (see class comment) but stored as raw
    # uuids: resolve them to a human label instead of leaking the id.
    ORGANIZATION_COLUMNS = %w[owner_organization_id source_organization_id].freeze
    PRINCIPAL_COLUMNS = %w[created_by_principal_id].freeze

    # Consistent with ChangeHistory::ActorResolver::UNKNOWN_LABEL: a raw uuid
    # is never an acceptable fallback for a person or an organization.
    UNKNOWN_ORGANIZATION_LABEL = 'Unknown organization'
    UNKNOWN_USER_LABEL = ActorResolver::UNKNOWN_LABEL

    # Per-column formatters, dispatched by name so format_value stays a
    # single lookup instead of a growing if/elsif chain.
    COLUMN_FORMATTERS = { 'visibility' => :visibility_name }
                        .merge(ENUM_COLUMNS.index_with { :enum_name })
                        .merge(ORGANIZATION_COLUMNS.index_with { :organization_name })
                        .merge(PRINCIPAL_COLUMNS.index_with { :principal_name })
                        .freeze

    def initialize(version)
      @version = version
    end

    def call
      changeset = safe_changeset
      return [] if changeset.blank?

      column_changes(changeset) + translation_changes(changeset)
    end

    private

    # Years-old history can contain payloads the safe YAML serializer refuses.
    # A timeline entry that cannot be parsed is rendered without a diff rather
    # than failing the whole query.
    def safe_changeset
      @version.changeset
    rescue StandardError => e
      Rails.logger.warn("ChangeHistory::DiffBuilder skipped version #{@version.id}: #{e.class}")
      nil
    end

    def column_changes(changeset)
      changeset.filter_map do |column, (before, after)|
        next if SKIPPED_COLUMNS.include?(column)

        rendered_before = format_value(column, before)
        rendered_after  = format_value(column, after)
        next if rendered_before == rendered_after

        { field: column.camelize(:lower), locale: nil, before: rendered_before, after: rendered_after }
      end
    end

    def translation_changes(changeset)
      before, after = changeset['translations']
      before = {} unless before.is_a?(Hash)
      after  = {} unless after.is_a?(Hash)

      (before.keys | after.keys).sort.flat_map do |locale|
        locale_changes(locale, before[locale] || {}, after[locale] || {})
      end
    end

    def locale_changes(locale, before, after)
      (before.keys | after.keys).sort.filter_map do |attribute|
        old_value = presence_of(before[attribute])
        new_value = presence_of(after[attribute])
        next if old_value == new_value

        { field: attribute.camelize(:lower), locale: locale, before: old_value, after: new_value }
      end
    end

    def presence_of(value)
      value&.to_s
    end

    def format_value(column, value)
      return nil if value.nil?

      formatter = COLUMN_FORMATTERS[column]
      return send(formatter, value) if formatter

      generic_format(value)
    end

    def generic_format(value)
      case value
      when Range then range_literal(value)
      when Time, DateTime, Date then value.iso8601
      else value.to_s
      end
    end

    def enum_name(value)
      value.to_s.upcase
    end

    # Ownership-transfer diffs must read as organization names, never raw
    # uuids: a deleted/unmirrored org id still renders a label, just not one
    # that leaks the id.
    def organization_name(value)
      Organization.find_by(id: value)&.name || UNKNOWN_ORGANIZATION_LABEL
    end

    def principal_name(value)
      principal = Principal.find_by(id: value)
      return UNKNOWN_USER_LABEL unless principal

      principal.display_name.presence || principal.email.presence || UNKNOWN_USER_LABEL
    end

    # AR's enum dirty-tracking reports the mapped string ('private'), so most
    # rows hit the upcase branch; older versions written before visibility was
    # declared as a Rails enum can still carry the raw integer, hence the
    # VISIBILITY_NAMES lookup for numeric values.
    def visibility_name(value)
      return VISIBILITY_NAMES[value] if value.is_a?(Integer)
      return VISIBILITY_NAMES[value.to_i] if value.to_s.match?(/\A\d+\z/)

      value.to_s.upcase
    end

    def range_literal(value)
      "[#{value.begin},#{value.end}#{value.exclude_end? ? ')' : ']'}"
    end
  end
end
