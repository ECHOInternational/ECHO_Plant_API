module Types
	class CategoryType
		class CategoryEdgeType < GraphQL::Types::Relay::BaseEdge
			node_type(Types::CategoryType)
		end
	end
end