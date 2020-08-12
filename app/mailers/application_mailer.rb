# frozen_string_literal: true

# Sets the defaults for Rails Mailer classes
class ApplicationMailer < ActionMailer::Base
  default from: 'from@example.com'
  layout 'mailer'
end
