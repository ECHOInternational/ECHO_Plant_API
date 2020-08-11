module Mutations
  class CreateImage < BaseMutation
    argument :image_id, ID, 'The ID for this image. This should be sourced from an upload.', required: true
    argument :object_id, ID, 'The ID for the object to which the image should be attached.', required: true
    argument :name, String, 'The translatable name of the image.', required: true
    argument :description, String, 'A translatable description of the image', required: false
    argument :attribution, String, 'The copyright or attribution statement for the image.', required: false
    argument :language, String, 'Language of the translatable fields supplied', required: false
    argument :bucket, String, 'The S3 bucket where the image is stored.', required: true
    argument :key, String, 'The S3 key for the image', required: true
    argument :visibility, Types::VisibilityEnum, 'The visibility of the image. Can be: PUBLIC, PRIVATE, DRAFT, DELETED', required: false, default_value: :private
    argument :image_attribute_ids, [ID], 'Attributes for the image', required: false

    field :image, Types::ImageType, null: true
    field :errors, [String], null: false

    def authorized?(**attributes)
      obj = PlantApiSchema.object_from_id(attributes[:object_id], {})
      authorize obj, :update?
    end

    def resolve(**attributes)
      language = attributes.delete(:language) || I18n.locale

      object_id = attributes.delete :object_id
      obj = PlantApiSchema.object_from_id(object_id, {})

      attributes[:s3_bucket] = attributes.delete :bucket
      attributes[:s3_key] = attributes.delete :key
      attributes[:id] = attributes.delete :image_id
      attributes[:created_by] = context[:current_user].email
      attributes[:owned_by] = context[:current_user].email
      attributes[:imageable] = obj

      # Check image attributes but don't fail on errors
      image_attributes = []

      attributes[:image_attribute_ids]&.each do |attribute_id|
        image_attribute = PlantApiSchema.object_from_id(attribute_id, {})
        image_attributes << image_attribute.id
      rescue ActiveRecord::RecordNotFound
        context.add_error(GraphQL::ExecutionError.new("ImageAttribute: #{attribute_id} not found."))
      end

      attributes[:image_attribute_ids] = image_attributes

      Mobility.with_locale(language) do
        image = Image.new(attributes)
        if image.save
          {
            image: image,
            errors: []
          }
        else
          {
            image: nil,
            errors: image.errors.full_messages
          }
        end
      end
    end
  end
end
