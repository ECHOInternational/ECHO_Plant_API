class ImagePolicy < OwnedResourcePolicy
    def show?
        return true if user && record.imageable.owned_by == user.email
        super
    end

    def update?
        if user && user.can_write?
            return true if record.imageable.owned_by == user.email
        end
        super
	end

    def destroy?
        if user && user.can_write?
            return true if record.imageable.owned_by == user.email
        end
        super
    end
    
    def create?
        # Images cannot be created directly they must be created through an imageable object.
        false
    end

end