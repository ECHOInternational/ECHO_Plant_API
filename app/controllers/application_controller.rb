# frozen_string_literal: true

# Controller for all application actions
class ApplicationController < ActionController::API
  include ActionController::HttpAuthentication::Token
  include ActionController::HttpAuthentication::Token::ControllerMethods
  before_action :set_locale
  before_action :require_token
  before_action :set_paper_trail_whodunnit
  # PaperTrail::Rails::Controller registers its own set_paper_trail_controller_info
  # before_action at include time, which runs BEFORE require_token resolves the
  # principal, so controller_info would never carry principal_id. Re-running it
  # here (after require_token) refreshes PaperTrail.request.controller_info with
  # the resolved actor. The earlier invocation is harmless.
  before_action :set_paper_trail_controller_info

  attr_reader :current_user

  DEFAULT_IDENTITY_ISSUER = 'https://www.echocommunity.org'

  private

  def set_locale
    detected_locale = http_accept_language.compatible_language_from(I18n.available_locales) || I18n.default_locale
    I18n.locale = detected_locale[0..1].downcase
  rescue I18n::InvalidLocale
    I18n.locale = I18n.default_locale
  end

  def require_token
    @current_user = nil
    return if set_sandbox_user

    public_key = jwt_public_key

    authenticate_with_http_token do |token, _options|
      jwt_payload = JWT.decode(
        token,
        public_key,
        true,
        { algorithm: ENV['APPLICATION_JWT_ALGORITHM'] }
      )
      @current_user = User.new(jwt_payload[0]['user'])
      resolve_actor(@current_user, jwt_payload[0]['iss'] || DEFAULT_IDENTITY_ISSUER)
    rescue JWT::DecodeError => e
      render json: JSON.pretty_generate(create_error_body(e.message, 401)), status: 401
    end
  end

  def jwt_public_key
    pub_key = <<~SECRET
      -----BEGIN PUBLIC KEY-----
      #{ENV['APPLICATION_JWT_SECRET']}
      -----END PUBLIC KEY-----
    SECRET

    OpenSSL::PKey::RSA.new(pub_key)
  end

  # Resolves the durable Principal for this request's user, provisions the
  # personal organization shim, and refreshes the local mirror rows for any
  # real organizations named in the token claim. All operations are
  # idempotent upserts on indexed lookups.
  def resolve_actor(user, issuer)
    return unless user&.id

    principal = Principal.resolve!(
      issuer: issuer,
      external_uid: user.id,
      email: user.email
    )
    user.principal = principal
    user.personal_organization = Organization.personal_for!(principal)
    user.organization_claims.each do |claim|
      Organization.mirror_real!(external_id: claim['id'], name: claim['name'])
    end
  end

  # Attached to every PaperTrail version created in this request
  # (versions.metadata jsonb). whodunnit already carries the JWT uid.
  def info_for_paper_trail
    meta = { origin: 'api' }
    meta[:principal_id] = @current_user.principal.id if @current_user&.principal
    { metadata: meta }
  end

  def set_sandbox_user
    return false unless ENV['SANDBOX'] == 'true'

    sandbox_trust_level = (ENV['SANDBOX_TRUST_LEVEL'] || '2').to_i
    @current_user = User.new(
      { 'uid' => 'sandbox', 'email' => 'sandbox@sandbox.com',
        'trust_levels' => { 'plant' => sandbox_trust_level } }
    )
    resolve_actor(@current_user, 'sandbox')
    true
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
