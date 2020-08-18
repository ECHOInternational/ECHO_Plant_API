# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlantPolicy, type: :policy do
  context 'when no user logged in' do
    let(:user) { nil }

    let(:target) { Plant }
    it { is_expected.to forbid_action(:create) }

    describe 'scope' do
      before :each do
        @public_plant = create(:plant, :public)
        @private_plant_not_owned = create(:plant, :private)
        # @private_plant_owned = create(:plant, :private, owned_by: user.id)
        @draft_plant_not_owned = create(:plant, :draft)
        # @draft_plant_owned = create(:plant, :draft, owned_by: user.id)
        @deleted_plant_not_owned = create(:plant, :deleted)
        # @deleted_plant_owned = create(:plant, :draft, owned_by: user.id)
      end

      it 'allows access to public records' do
        # expect(scope.to_a).to include(records[:public_plant])
        expect(scope.to_a).to include(@public_plant)
      end
      it 'does not allow access to private records' do
        expect(scope.to_a).to_not include(@private_plant_not_owned)
      end
      it 'does not allow access to draft records' do
        expect(scope.to_a).to_not include(@draft_plant_not_owned)
      end
      it 'does not allow access to deleted records' do
        expect(scope.to_a).to_not include(@deleted_plant_not_owned)
      end
    end

    context 'for public records' do
      let(:target) { build(:plant, :public) }
      it { is_expected.to permit_action(:show) }
      it { is_expected.to forbid_action(:update) }
      it { is_expected.to forbid_action(:destroy) }
    end
    context 'for draft records' do
      let(:target) { build(:plant, :draft) }
      it { is_expected.to forbid_action(:show) }
      it { is_expected.to forbid_action(:update) }
      it { is_expected.to forbid_action(:destroy) }
    end
    context 'for deleted records' do
      let(:target) { build(:plant, :deleted) }
      it { is_expected.to forbid_action(:show) }
      it { is_expected.to forbid_action(:update) }
      it { is_expected.to forbid_action(:destroy) }
    end
    context 'for private records' do
      let(:target) { build(:plant, :private) }
      it { is_expected.to forbid_action(:show) }
      it { is_expected.to forbid_action(:update) }
      it { is_expected.to forbid_action(:destroy) }
    end
  end

  context 'when user has read-only accesss' do
    let(:user) { build(:user, :readonly) }

    let(:target) { Plant }
    it { is_expected.to forbid_action(:create) }

    describe 'scope' do
      before :each do
        @public_plant = create(:plant, :public)
        @private_plant_not_owned = create(:plant, :private)
        @private_plant_owned = create(:plant, :private, owned_by: user.email)
        @draft_plant_not_owned = create(:plant, :draft)
        @draft_plant_owned = create(:plant, :draft, owned_by: user.email)
        @deleted_plant_not_owned = create(:plant, :deleted)
        @deleted_plant_owned = create(:plant, :draft, owned_by: user.email)
      end

      it 'allows access to public records' do
        expect(scope.to_a).to include(@public_plant)
      end
      context 'and the user does not own the record' do
        it 'does not allow access to private records' do
          expect(scope.to_a).to_not include(@private_plant_not_owned)
        end
        it 'does not allow access to draft records' do
          expect(scope.to_a).to_not include(@draft_plant_not_owned)
        end
        it 'does not allow access to deleted records' do
          expect(scope.to_a).to_not include(@deleted_plant_not_owned)
        end
      end
      context 'and the user owns the record' do
        it 'allows access to private records' do
          expect(scope.to_a).to include(@private_plant_owned)
        end
        it 'allows access to draft records' do
          expect(scope.to_a).to include(@draft_plant_owned)
        end
        it 'allows access to deleted records' do
          expect(scope.to_a).to include(@deleted_plant_owned)
        end
      end
    end

    context 'for public records' do
      let(:target) { build(:plant, :public) }
      it { is_expected.to permit_action(:show) }
      it { is_expected.to forbid_action(:update) }
      it { is_expected.to forbid_action(:destroy) }
    end
    context 'for draft records' do
      context 'when not owned by the user' do
        let(:target) { build(:plant, :draft, owned_by: 'no@no.com') }
        it { is_expected.to forbid_action(:show) }
        it { is_expected.to forbid_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:plant, :draft, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to forbid_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
    end
    context 'for deleted records' do
      context 'when not owned by the user' do
        let(:target) { build(:plant, :deleted, owned_by: 'no@no.com') }
        it { is_expected.to forbid_action(:show) }
        it { is_expected.to forbid_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:plant, :deleted, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to forbid_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
    end
    context 'for private records' do
      context 'when not owned by the user' do
        let(:target) { build(:plant, :private, owned_by: 'no@no.com') }
        it { is_expected.to forbid_action(:show) }
        it { is_expected.to forbid_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:plant, :private, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to forbid_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
    end
  end

  context 'when user has write accesss' do
    let(:user) { build(:user, :readwrite) }

    let(:target) { Plant }
    it { is_expected.to permit_action(:create) }

    context 'for public records' do
      let(:target) { build(:plant, :public) }
      it { is_expected.to permit_action(:show) }
      it { is_expected.to forbid_action(:update) }
      it { is_expected.to forbid_action(:destroy) }
    end
    context 'for draft records' do
      context 'when not owned by the user' do
        let(:target) { build(:plant, :draft, owned_by: 'no@no.com') }
        it { is_expected.to forbid_action(:show) }
        it { is_expected.to forbid_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:plant, :draft, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
    end
    context 'for deleted records' do
      context 'when not owned by the user' do
        let(:target) { build(:plant, :deleted, owned_by: 'no@no.com') }
        it { is_expected.to forbid_action(:show) }
        it { is_expected.to forbid_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:plant, :deleted, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
    end
    context 'for private records' do
      context 'when not owned by the user' do
        let(:target) { build(:plant, :private, owned_by: 'no@no.com') }
        it { is_expected.to forbid_action(:show) }
        it { is_expected.to forbid_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:plant, :private, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
    end
  end

  context 'when user is admin' do
    let(:user) { build(:user, :admin) }

    let(:target) { Plant }
    it { is_expected.to permit_action(:create) }

    describe 'scope' do
      before :each do
        @public_plant = create(:plant, :public)
        @private_plant_not_owned = create(:plant, :private)
        @private_plant_owned = create(:plant, :private, owned_by: user.email)
        @draft_plant_not_owned = create(:plant, :draft)
        @draft_plant_owned = create(:plant, :draft, owned_by: user.email)
        @deleted_plant_not_owned = create(:plant, :deleted)
        @deleted_plant_owned = create(:plant, :draft, owned_by: user.email)
      end

      it 'allows access to public records' do
        expect(scope.to_a).to include(@public_plant)
      end
      context 'and the user does not own the record' do
        it 'allows access to private records' do
          expect(scope.to_a).to include(@private_plant_not_owned)
        end
        it 'allows access to draft records' do
          expect(scope.to_a).to include(@draft_plant_not_owned)
        end
        it 'allows access to deleted records' do
          expect(scope.to_a).to include(@deleted_plant_not_owned)
        end
      end
      context 'and the user owns the record' do
        it 'allows access to private records' do
          expect(scope.to_a).to include(@private_plant_owned)
        end
        it 'allows access to draft records' do
          expect(scope.to_a).to include(@draft_plant_owned)
        end
        it 'allows access to deleted records' do
          expect(scope.to_a).to include(@deleted_plant_owned)
        end
      end
    end

    context 'for public records' do
      let(:target) { build(:plant, :public) }
      it { is_expected.to permit_action(:show) }
      it { is_expected.to permit_action(:update) }
      it { is_expected.to forbid_action(:destroy) }
    end
    context 'for draft records' do
      context 'when not owned by the user' do
        let(:target) { build(:plant, :draft, owned_by: 'no@no.com') }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:plant, :draft, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
    end
    context 'for deleted records' do
      context 'when not owned by the user' do
        let(:target) { build(:plant, :deleted, owned_by: 'no@no.com') }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:plant, :deleted, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
    end
    context 'for private records' do
      context 'when not owned by the user' do
        let(:target) { build(:plant, :private, owned_by: 'no@no.com') }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:plant, :private, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
    end
  end

  context 'when user is super admin' do
    let(:user) { build(:user, :superadmin) }

    let(:target) { Plant }
    it { is_expected.to permit_action(:create) }

    context 'for public records' do
      let(:target) { build(:plant, :public) }
      it { is_expected.to permit_action(:show) }
      it { is_expected.to permit_action(:update) }
      it { is_expected.to permit_action(:destroy) }
    end
    context 'for draft records' do
      context 'when not owned by the user' do
        let(:target) { build(:plant, :draft, owned_by: 'no@no.com') }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:plant, :draft, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
    end
    context 'for deleted records' do
      context 'when not owned by the user' do
        let(:target) { build(:plant, :deleted, owned_by: 'no@no.com') }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:plant, :deleted, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
    end
    context 'for private records' do
      context 'when not owned by the user' do
        let(:target) { build(:plant, :private, owned_by: 'no@no.com') }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:plant, :private, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
    end
  end
end
