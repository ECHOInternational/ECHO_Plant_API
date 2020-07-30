module Types
	class SortDirectionEnum < Types::BaseEnum
		graphql_name 'SortDirection'
		description 'Sets the direction returned records will be sorted'
		value 'ASC', value: :asc, description: "Ascending Order"
		value 'DESC', value: :desc, description: "Descending Order"
	end
end