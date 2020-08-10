module Mutations
	class AddImageAttributesToImage < BaseMutation
		argument :image_id, ID, required: true, loads: Types::ImageType
        argument :image_attribute_ids, [ID], required: true#, loads: Types::ImageAttributeType

		field :image, Types::ImageType, null:true
		field :errors, [String], null: false

        def authorized?(image:, **attributes)
			authorize image, :update?
		end

        def resolve(image:, **attributes)
                attributes[:image_attribute_ids].each do |attribute_id|
                    begin
                        image_attribute = PlantApiSchema.object_from_id(attribute_id, {})
                        image.image_attributes << image_attribute
                    rescue ActiveRecord::RecordNotFound
                        context.add_error(GraphQL::ExecutionError.new("ImageAttribute: #{attribute_id} not found."))
                    end
                end if attributes[:image_attribute_ids]
    
                {
                    image: image,
                    errors: []
                }

                # if image.update(attributes.except(:language))
				# 	{
				# 		image: image,
				# 		errors: []
				# 	}
				# else
				# 	{
				# 		image: image,
				# 		errors: image.errors.full_messages
				# 	}
                # end
		end
	end
end
