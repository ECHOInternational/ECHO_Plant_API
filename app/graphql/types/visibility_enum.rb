# frozen_string_literal: true

module Types
  # A reuseable enumerator for visibility values.
  class VisibilityEnum < Types::BaseEnum
    graphql_name 'Visibility'
    description 'Returns records based on visbility'
    value 'PRIVATE', value: :private, description: 'Request only records that are private (usually just those owned by the current user)'
    value 'PUBLIC', value: :public, description: 'Request only records that are public'
    value 'DRAFT', value: :draft, description: 'Request only records that are drafts'
    value 'DELETED', value: :deleted, description: 'Requesst only records that have been soft-deleted'
    value 'VISIBLE', value: :visible, description: 'Request public and private records'
  end
end
