# frozen_string_literal: true

module RelationSets
  # The `common_name_set` relation set (schema-delta item 8).
  #
  # Scope: only rows in MANAGED_LANGUAGES. Curator names in any other language
  # never enter the canonical string, so they are never digested, conflicted
  # on, or touched by the writer. EN carries the source's common names, UND
  # (ISO 639-3, "undetermined") its other-language names, which never become
  # a displayed primary name because Plant#primary_common_name_for_locale only
  # consults the requested locale and EN.
  #
  # Entry layout: [language, name, primary], sorted by language, then name
  # bytewise, then primary. `location` is outside the set: the writer keeps it
  # on matched rows, so a curator's annotation survives without counting as a
  # set edit.
  module CommonNames
    MANAGED_LANGUAGES = %w[EN UND].freeze
    EMPTY = '[]'

    module_function

    def empty
      EMPTY
    end

    # Canonical string of the plant's current managed rows, queried fresh.
    def read(plant)
      return EMPTY if plant.new_record?

      rows = CommonName.where(plant_id: plant.id, language: MANAGED_LANGUAGES).pluck(:language, :name, :primary)
      dump(normalize(rows.map { |language, name, primary| [language, name, primary == true] }))
    end

    # Accepts the canonical string (engine path) or a structured array (feed
    # and mutation path). Normalises, de-duplicates, sorts; raises
    # ArgumentError on anything that is not an array of [language, name,
    # primary] entries in a managed language.
    def parse(value)
      entries = value.is_a?(String) ? JSON.parse(value) : value
      raise ArgumentError, 'common_name_set must be an array' unless entries.is_a?(Array)

      normalize(entries.map { |entry| parse_entry(entry) })
    end

    def dump(entries)
      JSON.generate(entries)
    end

    # At most one primary per language; the source sends exactly one.
    def validate(_plant, entries)
      primaries = entries.select { |e| e[2] }.group_by(&:first)
      primaries.filter_map do |language, rows|
        "has #{rows.size} primary names in #{language}; at most one is allowed" if rows.size > 1
      end
    end

    # Diff against the current managed rows: match on [language, name.downcase],
    # create the missing, destroy the extra, and on matched rows adopt the
    # incoming casing and primary flag. Unmanaged languages are never touched.
    def apply(plant, entries)
      current = managed_rows(plant).index_by { |row| [row.language, row.name.downcase] }
      wanted = by_key(entries)
      current.each { |key, row| wanted.key?(key) ? adopt(row, wanted[key]) : row.destroy! }
      create_missing(plant, wanted.reject { |key, _entry| current.key?(key) })
    end

    def managed_rows(plant)
      CommonName.where(plant_id: plant.id, language: MANAGED_LANGUAGES)
    end

    def by_key(entries)
      entries.index_by { |language, name, _primary| [language, name.downcase] }
    end

    def create_missing(plant, entries_by_key)
      entries_by_key.each_value do |language, name, primary|
        CommonName.create!(plant_id: plant.id, language: language, name: name, primary: primary)
      end
    end

    # A matched row takes the incoming casing and primary flag; nothing else on it changes.
    def adopt(row, entry)
      changes = {}
      changes[:name] = entry[1] if row.name != entry[1]
      changes[:primary] = entry[2] if row.primary != entry[2]
      row.update!(changes) if changes.any?
    end

    def parse_entry(entry)
      raise ArgumentError, "common_name_set entry must be [language, name, primary], got #{entry.inspect}" unless well_formed?(entry)

      [parse_language(entry[0]), parse_name(entry[1]), entry[2]]
    end

    def well_formed?(entry)
      entry.is_a?(Array) && entry.size == 3 && entry[0].is_a?(String) && entry[1].is_a?(String) && [true, false].include?(entry[2])
    end

    def parse_language(value)
      language = value.strip.upcase
      raise ArgumentError, "common_name_set language #{language.inspect} is not managed (#{MANAGED_LANGUAGES.join(', ')})" unless MANAGED_LANGUAGES.include?(language)

      language
    end

    def parse_name(value)
      name = value.squish
      raise ArgumentError, 'common_name_set name must not be blank' if name.empty?

      name
    end

    def normalize(entries)
      seen = {}
      entries.each do |language, name, primary|
        key = [language, name.downcase]
        seen[key] = [language, name, primary] unless seen.key?(key)
      end
      seen.values.sort_by { |language, name, primary| [language, name.b, primary ? 1 : 0] }
    end
  end
end
