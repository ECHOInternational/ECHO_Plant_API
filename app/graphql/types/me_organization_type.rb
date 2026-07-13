# frozen_string_literal: true

module Types
  # One organization entry in the current user's membership list (me query).
  class MeOrganizationType < Types::BaseObject
    description 'An organization the current user belongs to, with their role in the plant domain.'

    field :organization, Types::OrganizationType, null: false,
                                                  description: 'The organization.'
    field :role, String, null: false,
                         description: 'The role the user holds in this organization for the plant domain.'

    def organization
      @object[:organization]
    end

    def role
      @object[:role]
    end
  end
end
