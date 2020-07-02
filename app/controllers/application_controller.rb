class ApplicationController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods
  before_action :require_token
  before_action :set_paper_trail_whodunnit

  def current_user
  	@current_user
  end

  private

  def require_token
  #   authenticate_or_request_with_http_token do |token|
  #     begin
  #       jwt_payload = JWT.decode(token, ENV['APPLICATION_JWT_SECRET'], true, { algorithm: ENV['APPLICATION_JWT_ALGORITHM']})
  #       @current_user = User.new(jwt_payload[0]["user"])
  #     rescue
  #       @current_user = nil
  #     end
  #   end
    @current_user = User.new({'uid' => 'test', 'email' => 'test@test.com', 'trust_levels' => {'plant' => 9}});
  end
end
