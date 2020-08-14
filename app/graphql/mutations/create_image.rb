# frozen_string_literal: true

module Mutations
  # Creates an Image
  class CreateImage < BaseMutation
    argument :image_id, ID,
             description: 'The ID for this image. This should be sourced from an upload.',
             required: true
    argument :object_id, ID,
             description: 'The ID for the object to which the image should be attached.',
             required: true
    argument :name, String,
             description: 'The translatable name of the image.',
             required: true
    argument :description, String,
             description: 'A translatable description of the image',
             required: false
    argument :attribution, String,
             description: 'The copyright or attribution statement for the image.',
             required: false
    argument :language, String,
             description: 'Language of the translatable fields supplied',
             required: false
    argument :bucket, String,
             description: 'The S3 bucket where the image is stored.',
             required: true
    argument :key, String,
             description: 'The S3 key for the image',
             required: true
    argument :visibility, Types::VisibilityEnum,
             description: 'The visibility of the image.',
             required: false,
             default_value: :private
    argument :image_attribute_ids, [ID],
             description: 'Attributes for the image',
             required: false

    field :image, Types::ImageType, null: true
    field :errors, [Types::MutationError], null: false

    def process_attributes(attributes)
      {
        s3_bucket: attributes[:bucket],
        s3_key: attributes[:key],
        id: attributes[:image_id],
        created_by: context[:current_user].email,
        owned_by: context[:current_user].email,
        name: attributes[:name],
        visibility: attributes[:visibility],
        description: attributes[:description],
        attribution: attributes[:attribution]
      }
    end

    def process_image_attributes(image_attributes)
      ids = []

      return ids unless image_attributes

      image_attributes.each do |attribute_id|
        image_attribute = PlantApiSchema.object_from_id(attribute_id, {})
        ids << image_attribute.id
      rescue ActiveRecord::RecordNotFound
        @errors << { field: 'imageAttributeIds', value: attribute_id, code: 404, message: "imageAttribute #{attribute_id} not found." }
      end

      ids
    end

    def authorized?(**attributes)
      obj = PlantApiSchema.object_from_id(attributes[:object_id], {})
      authorize obj, :update?
    end

    def resolve(**attributes)
      @errors = []
      image_attributes = process_attributes(attributes)
      # TODO: If imageable can't be found it should add to the @errors array?
      image_attributes[:imageable] = PlantApiSchema.object_from_id(attributes[:object_id], {})
      image_attributes[:image_attribute_ids] = process_image_attributes(attributes[:image_attribute_ids])

      Mobility.with_locale(attributes[:language] || I18n.locale) do
        image = Image.new(image_attributes)
        result = image.save
        errors = @errors + errors_from_active_record(image.errors, { id: 'imageId', s3_bucket: 'bucket', s3_key: 'key' })

        {
          image: result ? image : nil,
          errors: errors
        }
      end
    end
  end
end
