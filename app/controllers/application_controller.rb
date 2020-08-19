# frozen_string_literal: true

# Controller for all application actions
class ApplicationController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods
  before_action :set_locale
  before_action :require_token
  before_action :set_paper_trail_whodunnit

  attr_reader :current_user

  private

  def set_locale
    detected_locale = http_accept_language.compatible_language_from(I18n.available_locales) || I18n.default_locale
    I18n.locale = detected_locale[0..1].downcase
  rescue I18n::InvalidLocale
    I18n.locale = I18n.default_locale
  end

  def require_token
    # authenticate_or_request_with_http_token do |token|
    #   begin
    #     jwt_payload = JWT.decode(
    #       token,
    #       ENV['APPLICATION_JWT_SECRET'],
    #       true,
    #       { algorithm: ENV['APPLICATION_JWT_ALGORITHM']}
    #     )
    #     @current_user = User.new(jwt_payload[0]["user"])
    #   rescue
    #     @current_user = nil
    #   end
    # end
    @current_user = User.new({ 'uid' => 'test', 'email' => 'test@test.com', 'trust_levels' => { 'plant' => 9 } })
  end
end
