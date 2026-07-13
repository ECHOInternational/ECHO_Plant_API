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
    argument :successful, Boolean,
             description: 'Indicates if the user believes this was successful',
             required: false
    argument :recommended, Boolean,
             description: 'Indicates if the user would recommend this to others',
             required: false
    argument :saved_seed, Boolean,
             description: 'Indicates if the user saved seeds collected from this specimen',
             required: false
    argument :will_share_seed, Boolean,
             description: 'Indicates if the user plans to share seeds collected from this specimen',
             required: false
    argument :will_plant_again, Boolean,
             description: 'Indicates if the user plans to plant this again',
             required: false
    argument :notes, String,
             description: 'User supplied notes about the experience with this specimen',
             required: false
    argument :publication_state, Types::PublicationStateEnum,
             required: false,
             description: 'New publication state (DRAFT or PUBLISHED).'
    argument :access_level, Types::AccessLevelEnum,
             required: false,
             description: 'New access level (ORGANIZATION or PUBLIC).'

    field :specimen, Types::SpecimenType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(specimen:, **attributes)
      authorize specimen, :update?
      authorize_visibility_transition(specimen, attributes[:visibility])
      true
    end

    def resolve(specimen:, **attributes) # rubocop:disable all
      if attributes.key?(:visibility)
        Rails.logger.info(
          "legacy_contract.visibility_arg mutation=UpdateSpecimen specimen_id=#{specimen.id}"
        )
      end

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

      # When transitioning to deleted, stamp deleted_by_principal_id.
      vis = attributes[:visibility]
      if vis && vis.to_s.casecmp('deleted').zero? && specimen.visibility.to_s != 'deleted'
        attributes[:deleted_by_principal_id] = context[:current_user]&.principal&.id
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
