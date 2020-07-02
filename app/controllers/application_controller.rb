class ApplicationController < ActionController::API
	include Pundit
	before_action :set_paper_trail_whodunnit
end
