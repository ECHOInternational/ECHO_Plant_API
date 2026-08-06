# frozen_string_literal: true

module Types
  # One field-level before/after pair inside a change entry. Values are rendered
  # server-side: ranges as postgres literals, enums as their graphql names,
  # booleans as true/false.
  class FieldChangeType < Types::BaseObject
    description 'A single field level change, with server-rendered values.'

    field :field, String, null: false, hash_key: :field,
                          description: 'The camelCase graphql name of the changed field.'
    field :locale, String, null: true, hash_key: :locale,
                           description: 'The locale of a translated field, or null for untranslated fields.'
    field :before, String, null: true, hash_key: :before
    field :after, String, null: true, hash_key: :after
  end
end
