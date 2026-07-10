# frozen_string_literal: true

# Utility module for parsing CORS origins from ENV, with sensible defaults.
module CorsOrigins
  DEFAULT_ORIGINS = 'echocommunity.org,http://development.echocommunity.org:3000'

  def self.list
    origins_string = ENV.fetch('CORS_ORIGINS', DEFAULT_ORIGINS)
    origins_string.split(',').map(&:strip)
  end
end
