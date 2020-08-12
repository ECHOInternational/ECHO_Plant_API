# frozen_string_literal: true

module Mutations
  # Removes one or more ImageAttributes from a supplied Image
  class RemoveImageAttributesFromImage < BaseMutation
    argument :image_id, ID, required: true, loads: Types::ImageType
    argument :image_attribute_ids, [ID], required: true

    field :image, Types::ImageType, null: true
    field :errors, [String], null: false

    def authorized?(image:, **_attributes)
      authorize image, :update?
    end

    def resolve(image:, **attributes)
      attributes[:image_attribute_ids]&.each do |attribute_id|
        begin
          image_attribute = PlantApiSchema.object_from_id(attribute_id, {})
        rescue ActiveRecord::RecordNotFound
          context.add_error(GraphQL::ExecutionError.new("ImageAttribute: #{attribute_id} not found."))
        end

        next unless image_attribute

        begin
          join_record = ImageAttributesImage.find_by!(image_id: image.id, image_attribute_id: image_attribute.id)
          join_record.destroy
        rescue ActiveRecord::RecordNotFound
          context.add_error(GraphQL::ExecutionError.new("Image does not have associated attribute: #{attribute_id}"))
        end
      end

      {
        image: image,
        errors: []
      }
    end
  end
end
