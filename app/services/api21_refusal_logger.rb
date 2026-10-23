# frozen_string_literal: true

# Writes one structured log line whenever the API-21 query-cost limits refuse
# a request, so refusals can be counted in CloudWatch Logs Insights:
#
#   [api21_refusal] {"kind":"page_size","path":"plants",...}
#
# The line holds only: kind (page_size | depth | complexity), the field path
# and argument (page_size only), the requested value and the limit, the
# operation name when the client sent a valid GraphQL name, a boolean for
# whether the caller was authenticated, and the request id. It never holds
# query text, variables, user identifiers or IP addresses.
class Api21RefusalLogger
  PREFIX = '[api21_refusal]'
  OPERATION_NAME = /\A[_A-Za-z][_0-9A-Za-z]{0,99}\z/
  ANALYSIS_MESSAGES = {
    'depth' => /depth of (\d+), which exceeds max depth of (\d+)/,
    'complexity' => /complexity of (\d+), which exceeds max complexity of (\d+)/
  }.freeze

  # Called from the request path with the graphql-ruby query context. details
  # may hold requested:, limit:, path: and argument:.
  def self.log(kind:, context:, **details)
    operation_name = context[:operation_name]
    payload = {
      kind: kind,
      path: details[:path],
      argument: details[:argument],
      requested: details[:requested],
      limit: details[:limit],
      operation_name: (operation_name if operation_name.is_a?(String) && operation_name.match?(OPERATION_NAME)),
      authenticated: !context[:current_user].nil?,
      request_id: context[:request_id]
    }
    Rails.logger.info("#{PREFIX} #{payload.to_json}")
  end

  # Depth and complexity refusals are static analysis errors that graphql-ruby
  # reports in the result, not raised by our code, so read them off the result.
  def self.log_analysis_errors(result, context:)
    Array(result.to_h['errors']).each do |error|
      ANALYSIS_MESSAGES.each do |kind, pattern|
        match = pattern.match(error['message'].to_s)
        log(kind: kind, context: context, requested: match[1].to_i, limit: match[2].to_i) if match
      end
    end
  end
end
