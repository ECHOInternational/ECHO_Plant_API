# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FamilyPolicy, type: :policy do
  let(:target) { Family }

  context 'when no user is logged in' do
    let(:user) { nil }

    it { is_expected.to permit_action(:index) }
    it { is_expected.to permit_action(:show) }
    it { is_expected.to forbid_action(:create) }
    it { is_expected.to forbid_action(:update) }
    it { is_expected.to forbid_action(:destroy) }
  end

  context 'when the user has read-only access' do
    let(:user) { build(:user, :readonly) }

    it { is_expected.to permit_action(:show) }
    it { is_expected.to forbid_action(:update) }
  end

  context 'when the user has write access' do
    let(:user) { build(:user, :readwrite) }

    it { is_expected.to permit_action(:show) }
    it { is_expected.to forbid_action(:update) }
  end

  context 'when the user is an admin (trust 9)' do
    let(:user) { build(:user, :admin) }

    it { is_expected.to permit_action(:show) }
    it { is_expected.to permit_action(:update) }

    # The list itself stays immutable even for the people who edit its metadata.
    it { is_expected.to forbid_action(:create) }
    it { is_expected.to forbid_action(:destroy) }
  end

  context 'when the user is a super admin (trust 10)' do
    let(:user) { build(:user, :superadmin) }

    it { is_expected.to permit_action(:update) }
    it { is_expected.to forbid_action(:create) }
    it { is_expected.to forbid_action(:destroy) }
  end
end
