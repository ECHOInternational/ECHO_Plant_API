# frozen_string_literal: true

module Mutations
  # Updates a Plant Specimen
  class UpdateSpecimen < BaseMutation
    argument :specimen_id, ID, required: true, loads: Types::SpecimenType

    argument :name, String,
             required: false,
             description: 'The user assigned name of the specimen'
    argument :visibility, Types::VisibilityEnum,
             required: false,
             description: 'The visibility of the specimen'
    argument :plant_id, ID,
             required: false,
             description: 'The id of the plant to which this specimen is related'
    argument :variety_id, ID,
             required: false,
             description: 'The id of the variety to which this specimen is related'
    argument :terminated, Boolean,
             required: false,
             description: 'Indicates whether or not this plant is still growing'

    field :specimen, Types::SpecimenType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(specimen:, **_attributes)
      authorize specimen, :update?
    end

    def resolve(specimen:, **attributes) # rubocop:disable all
      errors = []
      if attributes[:plant_id]
        begin
          plant = PlantApiSchema.object_from_id(attributes[:plant_id], {})
        rescue ActiveRecord::RecordNotFound
          errors << {
            field: 'plantId',
            value: attributes[:plant_id],
            code: 404,
            message: "Plant #{attributes[:plant_id]} not found."
          }
        end
      end

      if attributes[:variety_id]
        begin
          variety = PlantApiSchema.object_from_id(attributes[:variety_id], {})
        rescue ActiveRecord::RecordNotFound
          errors << {
            field: 'varietyId',
            value: attributes[:variety_id],
            code: 404,
            message: "Variety #{attributes[:variety_id]} not found."
          }
        end
      end

      attributes.except!(:plant_id, :variety_id)
      attributes.merge!(plant_id: plant.id) if plant
      attributes.merge!(variety_id: variety.id) if variety

      result = specimen.update(attributes)
      errors += errors_from_active_record(specimen.errors)
      {
        specimen: result ? specimen : nil,
        errors: errors
      }
    end
  end
end
