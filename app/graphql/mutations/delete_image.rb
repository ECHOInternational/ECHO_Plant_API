module Mutations
  class DeleteImage < BaseMutation
    argument :image_id, ID, required: true, loads: Types::ImageType

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
