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
      id = image.id
      if image.destroy
        {
          image_id: id,
          errors: []
        }
      else
        {
          image_id: nil,
          errors: image.errors.full_messages
        }
      end
    end
  end
end
