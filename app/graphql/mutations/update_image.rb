# frozen_string_literal: true

module Mutations
  # Modifies editable fields for an Image
  class UpdateImage < BaseMutation
    argument :image_id, ID,
             description: 'The image to be updated.',
             required: true,
             loads: Types::ImageType
    argument :name, String,
             description: 'The translatable name of the image.',
             required: false
    argument :description, String,
             description: 'A translatable description of the image',
             required: false
    argument :language, String,
             description: 'Language of the translatable fields supplied',
             required: false
    argument :attribution, String,
             description: 'The copyright or attribution statement for the image.',
             required: false
    argument :visibility, Types::VisibilityEnum,
             description: 'The visibility of the image.',
             required: false

    field :image, Types::ImageType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(image:, **_attributes)
      authorize image, :update?
    end

    def resolve(image:, **attributes)
      language = attributes[:language] || I18n.locale

      Mobility.with_locale(language) do
        image.update(attributes.except(:language))
        {
          image: image,
          errors: errors_from_active_record(image.errors)
        }
      end
    end
  end
end
