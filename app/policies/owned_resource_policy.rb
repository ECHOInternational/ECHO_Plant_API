class OwnedResourcePolicy < ApplicationPolicy
	class Scope
		attr_reader :user, :scope
		def initialize(user, scope)
			@user = user
			@scope = scope
		end
		def resolve
			if user.admin?
				scope.all
			else
				scope.where(created_by: [user.id, "public"])
			end
		end

	end
	def index?
		true
	end
	
	def show?
		if user
			return true if user.admin?
			return true if record.owned_by == user.email
		end
		record.visibility_public?
	end

	def create?
		user && user.can_write?
	end

	def update?
		return false unless user && user.can_write?
		user.admin? || record.owned_by == user.email
	end

	def destroy?
		return false unless user && user.can_write?
		user.super_admin? || record.owned_by == user.email
	end
end