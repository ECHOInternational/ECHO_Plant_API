module Types
	class ImageAttributeType
		class ImageAttributeConnectionWithTotalCountType < GraphQL::Types::Relay::BaseConnection
			edge_type(ImageAttributeEdgeType)

			field :total_count, Integer, null: false
			def total_count
			  object.items.size
			end
		end
	end
end