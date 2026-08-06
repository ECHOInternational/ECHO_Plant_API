# frozen_string_literal: true

module Mutations
  module Concerns
    # Declares the shared familyId argument for plant create/update mutations,
    # and the mirror rule that keeps the legacy free-text family_names column
    # useful without ever clobbering text a human typed.
    module FamilyAssignment
      def self.included(base)
        base.argument :family_id, GraphQL::Types::ID,
                      required: false,
                      loads: Types::FamilyType,
                      description: 'The botanical family this plant belongs to'
      end

      # The legacy free-text column stays authoritative for whatever a human
      # typed. We only fill it in when it is empty, so a plant classified
      # through the new relation still shows something useful in the clients
      # that read family_names, without ever clobbering a person's own words.
      #
      # Callers MUST apply this only after every other attribute (including
      # any client-supplied family_names) has already been assigned to
      # plant, so the blank check below sees the value the client just sent
      # rather than a stale persisted one. This keeps create and update
      # consistent for a combined familyId + familyNames submission.
      def apply_family(plant, attributes)
        return unless attributes.key?(:family)

        family = attributes[:family]
        plant.family = family
        plant.family_names = family.name if family && plant.family_names.blank?
      end
    end
  end
end
