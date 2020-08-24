# frozen_string_literal: true

module Mutations
  # Updates a Plant Specimen
  class EvaluateSpecimen < BaseMutation
    argument :specimen_id, ID, required: true, loads: Types::SpecimenType

    argument :successful, Boolean,
             description: 'Indicates if the user believes this was successful',
             required: true
    argument :recommended, Boolean,
             description: 'Indicates if the user would recommend this to others',
             required: true
    argument :saved_seed, Boolean,
             description: 'Indicates if the user saved seeds collected from this specimen',
             required: true
    argument :will_share_seed, Boolean,
             description: 'Indicates if the user plans to share seeds collected from this specimen',
             required: true
    argument :will_plant_again, Boolean,
             description: 'Indicates if the user plans to plant this again',
             required: true
    argument :notes, String,
             description: 'User supplied notes about the experience with this specimen',
             required: false

    field :specimen, Types::SpecimenType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(specimen:, **_attributes)
      authorize specimen, :update?
    end

    def resolve(specimen:, **attributes)
      specimen.update(attributes)
      errors = errors_from_active_record(specimen.errors)
      {
        specimen: specimen,
        errors: errors
      }
    end
  end
end
