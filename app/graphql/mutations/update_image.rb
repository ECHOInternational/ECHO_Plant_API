module Mutations
	class UpdateImage < BaseMutation
		argument :image_id, ID, required: true, loads: Types::ImageType

		argument :name, String, required: false
		argument :description, String, required: false
        argument :language, String, required: false
        argument :attribution, String, required: false
		argument :visibility, Types::VisibilityEnum, required: false

		field :image, Types::ImageType, null:true
		field :errors, [String], null: false

		def authorized?(image:, **attributes)
			authorize image, :update?
		end

		def resolve(image:, **attributes)
			language = attributes[:language] || I18n.locale

			Mobility.with_locale(language) do
				if image.update(attributes.except(:language))
					{
						image: image,
						errors: []
					}
				else
					{
						image: image,
						errors: image.errors.full_messages
					}
				end
			end
		end
	end
end
