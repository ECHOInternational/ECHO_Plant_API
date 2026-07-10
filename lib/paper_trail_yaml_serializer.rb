# frozen_string_literal: true

require 'yaml'
require 'date'
require 'bigdecimal'

# Psych-4 safe YAML serializer for PaperTrail (the Ruby 3.1 rung).
#
# Why this exists:
#   Ruby 3.1 ships Psych 4, where YAML.load is safe_load by default and refuses
#   to instantiate arbitrary Ruby classes (Time, Date, ...) unless they are on
#   an explicit allowlist. PaperTrail stores each version's `object` column as a
#   YAML dump of the record's attributes, so loading old history must tolerate
#   the non-scalar types those attributes serialize to (timestamps, etc.).
#
#   PaperTrail 12.3's built-in serializer sidesteps Psych 4 by calling
#   YAML.unsafe_load when it is available - which restores the pre-4 permissive
#   behaviour but re-opens the arbitrary-deserialization surface Psych 4 closed.
#   We replace that with YAML.safe_load and a minimal permitted_classes allowlist
#   so history stays reify-able WITHOUT unsafe loading.
#
# Why ActiveRecord's yaml flags cannot do this:
#   Rails' yaml_column_permitted_classes / use_yaml_unsafe_load only govern
#   ActiveRecord's own YAML coder. PaperTrail serializes versions.object through
#   its own serializer (this module / PT's default), never AR's coder, so those
#   flags never reach this code path. The fix has to live at the PaperTrail
#   serializer level - here.
#
# permitted_classes:
#   Time is the class the real PT-10 production payload (and the compat-spec
#   fixture) contains (bare-Time created_at / updated_at from a pre-zone dump).
#   ActiveSupport::TimeWithZone + ActiveSupport::TimeZone are what a Rails 7.0
#   PT dump now serializes timestamps to (a TimeWithZone nests a TimeZone), which
#   the live create/update reify path proved necessary. Date, DateTime and
#   BigDecimal are the other temporal/numeric types AR attributes serialize to
#   across the model set; Symbol covers symbol-keyed payloads. aliases: true
#   preserves the YAML anchor/alias support PT dumps rely on (TimeWithZone dumps
#   an anchor when created_at == updated_at). Range is required because Plant and
#   Variety carry Postgres numrange columns whose attribute values serialize to
#   Ruby Range objects. Add to this list only when a failing reify proves a new
#   class is genuinely present in stored history.
module PaperTrailYamlSerializer
  # Base permitted classes resolved at load time (no AR connection needed).
  PERMITTED_CLASSES = [
    Time,
    Date,
    DateTime,
    BigDecimal,
    Symbol,
    Range,
    ActiveSupport::TimeWithZone,
    ActiveSupport::TimeZone
  ].freeze

  # Expose these as module methods (PaperTrail.serializer.load/dump) while keeping
  # them usable as instance methods too; mirrors PaperTrail::Serializers::YAML.
  module_function

  # Returns the full permitted-class list, resolving AR adapter classes lazily
  # so this file can be required before the PostgreSQL adapter is loaded.
  #
  # ActiveRecord::Point (Location#latlng point column) is defined in the PG OID
  # layer and is only available after the first DB connection is established.
  # Forward-risk only - production history contains zero Point payloads as of
  # 2026-07-10 (tag-scan of all versions rows).
  def permitted_classes
    base = PERMITTED_CLASSES
    ar_point = ::ActiveRecord::Point if defined?(::ActiveRecord::Point)
    ar_point ? base + [ar_point] : base
  end

  def load(string)
    ::YAML.safe_load(string, permitted_classes: permitted_classes, aliases: true)
  end

  def dump(object)
    object = object.to_hash if object.is_a?(ActiveSupport::HashWithIndifferentAccess)
    ::YAML.dump(object)
  end

  # Mirrors PaperTrail::Serializers::YAML so `where_object` queries keep working.
  def where_object_condition(arel_field, field, value)
    arel_field.matches("%\n#{field}: #{value}\n%")
  end
end
