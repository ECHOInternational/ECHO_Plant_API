class ImageAttributePolicy < ApplicationPolicy
	def index?
		true
	end
	
	def show?
		true
	end

	def create?
		user && user.super_admin?
	end

	def update?
		create?
	end

	def destroy?
		create?
	end
end