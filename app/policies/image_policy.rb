class ImagePolicy < OwnedResourcePolicy
    class Scope
        attr_reader :user, :scope
        
		def initialize(user, scope)
			@user = user
			@scope = scope
		end
		def resolve
			# if user && user.admin?
			# 	scope.all
			# elsif user
			# 	scope.where(visibility: :public).or(scope.where(owned_by: user.email))
			# else
			# 	scope.where(visibility: :public)
            # end
            scope.all
		end

	end
    def show?
		if user
			return true if user.admin?
			return true if record.owned_by == user.email
		end
		record.imageable.visibility_public?
	end
end