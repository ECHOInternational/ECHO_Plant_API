# frozen_string_literal: true

module Mutations
  # Updates the metadata ECHO layers on top of the locked family list.
  #
  # This deliberately does NOT use Mutations::Lookups::UpdateLookupBaseMutation.
  # Those base classes come as a create/update/delete trio and their shared spec
  # generator assumes all three exist; adopting them would hand us exactly the
  # create and delete mutations that must not exist for families.
  #
  # There is no name, colId or kingdom argument. The list is fixed; only the
  # annotations are editable.
  class UpdateFamily < BaseMutation
    argument :family_id, GraphQL::Types::ID,
             required: true,
             loads: Types::FamilyType,
             description: 'The family whose metadata is being edited'
    argument :description, String,
             required: false,
             description: 'Translatable description of the family'
    argument :seed_banking_notes, String,
             required: false,
             description: 'Translatable notes on seed banking suitability'
    argument :storage_physiology, String,
             required: false,
             description: 'orthodox, recalcitrant, intermediate, variable, mixed or unknown'
    argument :seed_longevity, String,
             required: false,
             description: 'low, low_medium, medium, medium_high or high'
    argument :seed_banking_rank, Integer,
             required: false,
             description: 'Seed banking suitability from 1 (poor) to 5 (excellent)'
    argument :language, String,
             required: false,
             description: 'Language of the translatable fields supplied'

    field :family, Types::FamilyType, null: true
    field :errors, [Types::MutationError], null: false

    include Mutations::Concerns::DraftWriting

    TRANSLATED = %i[description seed_banking_notes].freeze
    PLAIN = %i[storage_physiology seed_longevity seed_banking_rank].freeze

    def authorized?(**attributes)
      authorize attributes[:family], :update?
    end

    def resolve(**attributes)
      family = attributes[:family]
      language = attributes[:language] || I18n.locale

      if attributes.delete(:save_as_draft)
        draft = write_draft(family, attributes.except(:family), language: language)
        return { family: family, errors: [] } if draft.persisted?
      end

      write_live(family, attributes, language)
    end

    private

    def write_live(family, attributes, language)
      Mobility.with_locale(language) do
        TRANSLATED.each { |key| family.public_send("#{key}=", attributes[key]) if attributes.key?(key) }
        PLAIN.each { |key| family.public_send("#{key}=", attributes[key]) if attributes.key?(key) }
        family.save

        {
          family: family,
          errors: errors_from_active_record(family.errors)
        }
      end
    end
  end
end
