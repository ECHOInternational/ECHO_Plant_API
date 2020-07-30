module Types
	class CategoryType
		class CategoryConnectionWithTotalCountType < GraphQL::Types::Relay::BaseConnection
			edge_type(CategoryEdgeType)

			field :total_count, Integer, null: false
			def total_count
			  object.items.size
			end
		end
	end
end