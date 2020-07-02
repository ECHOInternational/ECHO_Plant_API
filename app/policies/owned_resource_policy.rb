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
		user.can_read?
	end
	
	def show?
		user.can_read?
	end

	def create?
		user.can_write?
	end

	def update?
		user.admin? || record.created_by == user.id
	end

	def destroy?
		if record.created_by == "public"
			return user.super_admin?
		else
			user.admin? || record.created_by == user.id
		end
	end
end