# frozen_string_literal: true

module Mutations
  # Deletes an Image
  class DeleteImage < BaseMutation
    argument :image_id, ID,
             description: 'The image to be deleted',
             required: true,
             loads: Types::ImageType

    field :image_id, ID, null: true
    field :errors, [String], null: false

    def authorized?(image:, **_attributes)
      authorize image, :destroy?
    end

    def resolve(image:, **_attributes)
      id = PlantApiSchema.id_from_object(image, Image, {})
      result = image.destroy
      errors = errors_from_active_record image.errors
      {
        image_id: result.destroyed? ? id : nil,
        errors: errors
      }
    end
  end
end
