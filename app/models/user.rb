class User
	extend ActiveModel::Naming
	attr_reader :id
	attr_reader :email
	attr_reader :permissions

	def initialize(options)
		@id = options["uid"]
		@email = options["email"]
		@permissions = options["trust_levels"]
	end

	# plant permissions
	# 0 = No Access
	# 1 = Read-Only Access
	# 2 = Read/Write Access
	# 3 ... 7 Future Use
	# 8 Can Create, Update, and Delete on behalf of other users and can 
	#   Create and update public records... Cannot delete public records.
	# 9 Can delete public records

	def super_admin?
		@permissions["plant"] > 8
	end

	def admin?
		# Can CRUD things with restricted ownership
		@permissions["plant"] > 7
	end

	def can_read?
		@permissions["plant"] > 0
	end

	def can_write?
		@permissions["plant"] > 1
	end 

	def to_model
	end

	def to_s
		@id
	end

	# def inspect
	# 	@id
	# end

	def persisted?
		false
	end
end