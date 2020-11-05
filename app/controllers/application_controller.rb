# frozen_string_literal: true

# Controller for all application actions
class ApplicationController < ActionController::API
  include ActionController::HttpAuthentication::Token
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
    @current_user = nil

    pub_key = <<-SECRET
-----BEGIN PUBLIC KEY-----
#{ENV['APPLICATION_JWT_SECRET']}
-----END PUBLIC KEY-----
SECRET

    public_key = OpenSSL::PKey::RSA.new(pub_key)
    if ENV['SANDBOX'] == "true"
      @current_user = User.new(
        { 'uid' => 'sandbox', 'email' => 'sandbox@sandbox.com', 'trust_levels' => { 'plant' => 2 } }
      )
      return
    end

    authenticate_with_http_token do |token, _options|
      jwt_payload = JWT.decode(
        token,
        public_key,
        true,
        { algorithm: ENV['APPLICATION_JWT_ALGORITHM'] }
      )
      @current_user = User.new(jwt_payload[0]['user'])
    rescue JWT::DecodeError => e
      render json: JSON.pretty_generate(create_error_body(e.message, 401)), status: 401
    end
  end
end

def create_error_body(message, code)
  {
    data: nil,
    errors: [
      {
        message: "Token Error: #{message}",
        extensions: {
          code: code
        }
      }
    ]
  }
end
