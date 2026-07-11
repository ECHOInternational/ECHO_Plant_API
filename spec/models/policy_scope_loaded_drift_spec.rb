# frozen_string_literal: true

require 'rails_helper'

# This spec exists so any future change to OwnedResourcePolicy::Scope forces the
# same change in Types::PlantType#policy_scope_loaded. That method is an in-Ruby
# transcription of OwnedResourcePolicy::Scope#resolve used on the eager-loaded
# varieties path; if the two ever drift, the loaded list would return a
# different visible set than the SQL policy scope. These parameterized examples
# call the REAL Types::PlantType#policy_scope_loaded and assert its id-set
# EXACTLY equals OwnedResourcePolicy::Scope.new(user, plant.varieties).resolve's
# id-set for every trust tier, so a change to one without the other fails here.
RSpec.describe 'policy_scope_loaded drift guard', type: :model do
  let(:owner_email) { 'owner@example.com' }
  let(:other_email) { 'other@example.com' }

  # A real PlantType instance whose public policy_scope_loaded we exercise
  # directly (object/context are unused by that method). graphql-ruby marks
  # .new protected, so allocate the instance without running the type's
  # authorization hooks.
  let(:plant_type_instance) { Types::PlantType.allocate }

  let(:plant) { create(:plant, :public) }

  let!(:public_variety) do
    create(:variety, :public, plant: plant, owned_by: other_email)
  end
  let!(:owned_private_variety) do
    create(:variety, :private, plant: plant, owned_by: owner_email)
  end
  let!(:other_private_variety) do
    create(:variety, :private, plant: plant, owned_by: other_email)
  end

  def loaded_ids(user)
    plant_type_instance.policy_scope_loaded(user, plant.varieties.to_a).to_set(&:id)
  end

  def sql_ids(user)
    OwnedResourcePolicy::Scope.new(user, plant.varieties).resolve.to_set(&:id)
  end

  {
    'super-admin (trust 10)' => -> { build(:user, :superadmin, email: 'owner@example.com') },
    'admin (trust 9)' => -> { build(:user, :admin, email: 'owner@example.com') },
    'write-owner (trust 2)' => -> { build(:user, :readwrite, email: 'owner@example.com') },
    'write-non-owner (trust 2)' => -> { build(:user, :readwrite, email: 'other@example.com') },
    'read-only (trust 1)' => -> { build(:user, :readonly, email: 'owner@example.com') },
    'nil user' => -> {}
  }.each do |label, user_builder|
    it "matches OwnedResourcePolicy::Scope for #{label}" do
      user = instance_exec(&user_builder)

      expect(loaded_ids(user)).to eq(sql_ids(user))
    end
  end
end
