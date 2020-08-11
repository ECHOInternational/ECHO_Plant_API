# frozen_string_literal: true

require 'pundit/rspec'

RSpec.shared_context 'Policy' do
  subject { described_class.new(user, target) }
  let(:model_class) { described_class.to_s.chomp('Policy').constantize }
  # let(:permitted_attributes) do
  #   described_class.new(User.new, model_class).permitted_attributes
  # end
  let(:user) { build(:user, :readonly) }
  let(:scope) { Pundit.policy_scope!(user, model_class) }
end

RSpec.configure do |config|
  config.include_context 'Policy', type: :policy
end
