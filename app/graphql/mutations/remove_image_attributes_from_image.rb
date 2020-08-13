# frozen_string_literal: true

module Mutations
  # Removes one or more ImageAttributes from a supplied Image
  class RemoveImageAttributesFromImage < BaseMutation
    argument :image_id, ID,
             description: 'ID for image from which the attribute(s) should be removed',
             required: true,
             loads: Types::ImageType
    argument :image_attribute_ids, [ID],
             description: 'ID(s) of the image attributes that should be removed from the image',
             required: true

    field :image, Types::ImageType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(image:, **_attributes)
      authorize image, :update?
    end

    def resolve(image:, **attributes) # rubocop:disable Metrics/MethodLength
      errors = []
      attributes[:image_attribute_ids]&.each do |attribute_id|
        begin
          image_attribute = PlantApiSchema.object_from_id(attribute_id, {})
        rescue ActiveRecord::RecordNotFound
          errors << {
            field: 'imageAttributeIds',
            value: attribute_id,
            message: "ImageAttribute #{attribute_id} not found.",
            code: 404
          }
        end

        next unless image_attribute

        begin
          join_record = ImageAttributesImage.find_by!(image_id: image.id, image_attribute_id: image_attribute.id)
          join_record.destroy
        rescue ActiveRecord::RecordNotFound
          errors << {
            field: 'imageAttributeIds',
            value: attribute_id,
            message: "Image does not have associated attribute: #{attribute_id}.",
            code: 404
          }
        end
      end

      {
        image: image,
        errors: errors
      }
    end
  end
end
