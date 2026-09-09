# frozen_string_literal: true

# Exposes a set of join rows as one virtual attribute, so SourceSynchronizer
# can read, digest, apply and raise conflicts on it exactly like a column
# (fpi-connector decisions 17 and 33; schema-delta item 7).
#
#   include RelationSets
#   relation_set :category_set, serializer: RelationSets::Categories
#
# The reader returns the canonical string of the plant's CURRENT join rows,
# produced by the serializer's one `dump` function -- the same function the
# feed uses on the incoming side, so the two sides can only agree or differ on
# content, never on formatting. The writer parses and shape-checks a value,
# stages it, and does nothing at all when the canonical strings already match:
# an unchanged set writes no join rows and versions nothing. Staged sets are
# validated with the record (an unknown category id is a validation error, so
# the engine counts the row `invalid` and touches no join row) and applied in
# after_save, inside the save's transaction, so a join-row failure rolls the
# whole save back and the engine counts it `errored`.
#
# Three rules the concern must keep (verified against the engine):
#   1. `read` queries the join rows fresh, never a cached association target,
#      or a set written earlier in the same request reads stale.
#   2. after_save clears the staging before applying, and `reload` clears it
#      too, because the engine reloads the record after RecordInvalid.
#   3. Direct writes (`plant.categories = ...`, `CommonName.create!`) bypass the
#      writer and are seen only through the reader.
module RelationSets
  extend ActiveSupport::Concern

  class_methods do
    def relation_set(name, serializer:)
      relation_set_serializers[name] = serializer
      define_method(name) { serializer.read(self) }
      define_method(:"#{name}=") do |value|
        parsed = serializer.parse(value)
        if serializer.dump(parsed) == serializer.read(self)
          staged_relation_sets.delete(name)
        else
          staged_relation_sets[name] = parsed
        end
      end
    end

    def relation_set_serializers
      @relation_set_serializers ||= {}
    end
  end

  included do
    validate :validate_staged_relation_sets
    after_save :apply_staged_relation_sets
  end

  def staged_relation_sets
    @staged_relation_sets ||= {}
  end

  def reload(*)
    @staged_relation_sets = {}
    super
  end

  private

  def validate_staged_relation_sets
    staged_relation_sets.each do |name, parsed|
      self.class.relation_set_serializers.fetch(name).validate(self, parsed).each do |message|
        errors.add(name, message)
      end
    end
  end

  def apply_staged_relation_sets
    staged = staged_relation_sets
    @staged_relation_sets = {}
    staged.each do |name, parsed|
      self.class.relation_set_serializers.fetch(name).apply(self, parsed)
    end
  end
end
