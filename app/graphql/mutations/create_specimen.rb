# frozen_string_literal: true

module Mutations
  # Creates a Plant Specimen
  class CreateSpecimen < BaseMutation
    argument :name, String,
             required: true,
             description: 'The user assigned name of the specimen'
    argument :visibility, Types::VisibilityEnum,
             required: false,
             description: 'The visibility of the specimen'
    argument :plant_id, ID,
             required: true,
             description: 'The id of the plant to which this specimen is related'
    argument :variety_id, ID,
             required: false,
             description: 'The id of the variety to which this specimen is related'
    argument :organization_id, ID,
             required: false,
             description: 'Relay global ID of the organization on whose behalf this specimen is created. Defaults to the personal organization.'

    field :specimen, Types::SpecimenType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(**_attributes)
      authorize Specimen, :create?
    end

    def resolve(**attributes) # rubocop:disable all
      errors = []
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

      org_id_arg = attributes.delete(:organization_id)
      if org_id_arg
        stamp, err = acting_organization_stamp(org_id_arg)
        return { specimen: nil, errors: [err] } if err

        org_stamp = stamp
      else
        org_stamp = ownership_stamp
      end

      attributes
        .except!(:plant_id, :variety_id)
        .merge!(created_by: context[:current_user].email)
        .merge!(owned_by: context[:current_user].email)
        .merge!(org_stamp)

      specimen = Specimen.new(attributes)
      specimen.plant = plant
      specimen.variety = variety if variety
      result = specimen.save
      errors += errors_from_active_record(specimen.errors)
      {
        specimen: result ? specimen : nil,
        errors: errors
      }
    end
  end
end
