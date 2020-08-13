# frozen_string_literal: true

module Mutations
  # Adds one or more ImageAttributes to a supplied Image Object
  class AddImageAttributesToImage < BaseMutation
    argument :image_id, ID,
             required: true,
             loads: Types::ImageType,
             description: 'ID for image to which the attribute(s) should be added'

    argument :image_attribute_ids, [ID],
             required: true,
             description: 'ID(s) of the image attributes that should be associated with the image'

    field :image, Types::ImageType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(image:, **_attributes)
      authorize image, :update?
    end

    def resolve(image:, **attributes)
      errors = []
      attributes[:image_attribute_ids]&.each do |attribute_id|
        image_attribute = PlantApiSchema.object_from_id(attribute_id, {})
        image.image_attributes << image_attribute
      rescue ActiveRecord::RecordNotFound
        errors << {
          field: 'imageAttributeIds',
          value: attribute_id,
          message: "ImageAttribute #{attribute_id} not found.",
          code: 404
        }
      end

      {
        image: image,
        errors: errors
      }
    end
  end
end
