require 'rails_helper'

RSpec.describe ImagePolicy, type: :policy do
  context 'when no user logged in' do
    let(:user) { nil }

    let(:target) { Image }
    it { is_expected.to forbid_action(:create) }

    describe 'scope' do
      before :each do
        @public_image = create(:image, :public)
        @private_image_not_owned = create(:image, :private)
        @draft_image_not_owned = create(:image, :draft)
        @deleted_image_not_owned = create(:image, :deleted)
      end

      it 'allows access to public records' do
        expect(scope.to_a).to include(@public_image)
      end
      it 'does not allow access to private records' do
        expect(scope.to_a).to_not include(@private_image_not_owned)
      end
      it 'does not allow access to draft records' do
        expect(scope.to_a).to_not include(@draft_image_not_owned)
      end
      it 'does not allow access to deleted records' do
        expect(scope.to_a).to_not include(@deleted_image_not_owned)
      end
    end

    context 'for public records' do
      let(:target) { build(:image, :public) }
      it { is_expected.to permit_action(:show) }
      it { is_expected.to forbid_action(:update) }
      it { is_expected.to forbid_action(:destroy) }
    end
    context 'for draft records' do
      let(:target) { build(:image, :draft) }
      it { is_expected.to forbid_action(:show) }
      it { is_expected.to forbid_action(:update) }
      it { is_expected.to forbid_action(:destroy) }
    end
    context 'for deleted records' do
      let(:target) { build(:image, :deleted) }
      it { is_expected.to forbid_action(:show) }
      it { is_expected.to forbid_action(:update) }
      it { is_expected.to forbid_action(:destroy) }
    end
    context 'for private records' do
      let(:target) { build(:image, :private) }
      it { is_expected.to forbid_action(:show) }
      it { is_expected.to forbid_action(:update) }
      it { is_expected.to forbid_action(:destroy) }
    end
  end

  context 'when user has read-only accesss' do
    let(:user) { build(:user, :readonly) }

    let(:target) { Image }
    it { is_expected.to forbid_action(:create) }

    describe 'scope' do
      before :each do
        @public_image = create(:image, :public)
        @private_image_not_owned = create(:image, :private)
        @private_image_owned = create(:image, :private, owned_by: user.email)
        @draft_image_not_owned = create(:image, :draft)
        @draft_image_owned = create(:image, :draft, owned_by: user.email)
        @deleted_image_not_owned = create(:image, :deleted)
        @deleted_image_owned = create(:image, :draft, owned_by: user.email)
      end

      it 'allows access to public records' do
        expect(scope.to_a).to include(@public_image)
      end
      context 'and the user does not own the record' do
        it 'does not allow access to private records' do
          expect(scope.to_a).to_not include(@private_image_not_owned)
        end
        it 'does not allow access to draft records' do
          expect(scope.to_a).to_not include(@draft_image_not_owned)
        end
        it 'does not allow access to deleted records' do
          expect(scope.to_a).to_not include(@deleted_image_not_owned)
        end
      end
      context 'and the user owns the record' do
        it 'allows access to private records' do
          expect(scope.to_a).to include(@private_image_owned)
        end
        it 'allows access to draft records' do
          expect(scope.to_a).to include(@draft_image_owned)
        end
        it 'allows access to deleted records' do
          expect(scope.to_a).to include(@deleted_image_owned)
        end
      end
    end

    context 'for public records' do
      let(:target) { build(:image, :public) }
      it { is_expected.to permit_action(:show) }
      it { is_expected.to forbid_action(:update) }
      it { is_expected.to forbid_action(:destroy) }
    end
    context 'for draft records' do
      context 'when not owned by the user' do
        let(:target) { build(:image, :draft, owned_by: "no@no.com") }
        it { is_expected.to forbid_action(:show) }
        it { is_expected.to forbid_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:image, :draft, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to forbid_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
    end
    context 'for deleted records' do
      context 'when not owned by the user' do
        let(:target) { build(:image, :deleted, owned_by: "no@no.com") }
        it { is_expected.to forbid_action(:show) }
        it { is_expected.to forbid_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:image, :deleted, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to forbid_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
    end
    context 'for private records' do
      context 'when not owned by the user' do
        let(:target) { build(:image, :private, owned_by: "no@no.com") }
        it { is_expected.to forbid_action(:show) }
        it { is_expected.to forbid_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:image, :private, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to forbid_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
    end
  end

  context 'when user has write accesss' do
    let(:user) { build(:user, :readwrite) }

    let(:target) { Image }
    it { is_expected.to forbid_action(:create) }

    context 'for public records' do
      let(:target) { build(:image, :public) }
      it { is_expected.to permit_action(:show) }
      it { is_expected.to forbid_action(:update) }
      it { is_expected.to forbid_action(:destroy) }
    end
    context 'for draft records' do
      context 'when not owned by the user' do
        let(:target) { build(:image, :draft, owned_by: "no@no.com") }
        it { is_expected.to forbid_action(:show) }
        it { is_expected.to forbid_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:image, :draft, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
    end
    context 'for deleted records' do
      context 'when not owned by the user' do
        let(:target) { build(:image, :deleted, owned_by: "no@no.com") }
        it { is_expected.to forbid_action(:show) }
        it { is_expected.to forbid_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:image, :deleted, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
    end
    context 'for private records' do
      context 'when not owned by the user' do
        let(:target) { build(:image, :private, owned_by: "no@no.com") }
        it { is_expected.to forbid_action(:show) }
        it { is_expected.to forbid_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:image, :private, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
    end
  end

  context 'when user is admin' do
    let(:user) { build(:user, :admin) }

    let(:target) { Image }
    it { is_expected.to forbid_action(:create) }

    describe 'scope' do
      before :each do
        @public_image = create(:image, :public)
        @private_image_not_owned = create(:image, :private)
        @private_image_owned = create(:image, :private, owned_by: user.email)
        @draft_image_not_owned = create(:image, :draft)
        @draft_image_owned = create(:image, :draft, owned_by: user.email)
        @deleted_image_not_owned = create(:image, :deleted)
        @deleted_image_owned = create(:image, :draft, owned_by: user.email)
      end

      it 'allows access to public records' do
        expect(scope.to_a).to include(@public_image)
      end
      context 'and the user does not own the record' do
        it 'allows access to private records' do
          expect(scope.to_a).to include(@private_image_not_owned)
        end
        it 'allows access to draft records' do
          expect(scope.to_a).to include(@draft_image_not_owned)
        end
        it 'allows access to deleted records' do
          expect(scope.to_a).to include(@deleted_image_not_owned)
        end
      end
      context 'and the user owns the record' do
        it 'allows access to private records' do
          expect(scope.to_a).to include(@private_image_owned)
        end
        it 'allows access to draft records' do
          expect(scope.to_a).to include(@draft_image_owned)
        end
        it 'allows access to deleted records' do
          expect(scope.to_a).to include(@deleted_image_owned)
        end
      end
    end

    context 'for public records' do
      let(:target) { build(:image, :public) }
      it { is_expected.to permit_action(:show) }
      it { is_expected.to permit_action(:update) }
      it { is_expected.to forbid_action(:destroy) }
    end
    context 'for draft records' do
      context 'when not owned by the user' do
        let(:target) { build(:image, :draft, owned_by: "no@no.com") }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:image, :draft, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
    end
    context 'for deleted records' do
      context 'when not owned by the user' do
        let(:target) { build(:image, :deleted, owned_by: "no@no.com") }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:image, :deleted, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
    end
    context 'for private records' do
      context 'when not owned by the user' do
        let(:target) { build(:image, :private, owned_by: "no@no.com") }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to forbid_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:image, :private, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
    end
  end

  context 'when user is super admin' do
    let(:user) { build(:user, :superadmin) }

    let(:target) { Image }
    it { is_expected.to forbid_action(:create) }

    context 'for public records' do
      let(:target) { build(:image, :public) }
      it { is_expected.to permit_action(:show) }
      it { is_expected.to permit_action(:update) }
      it { is_expected.to permit_action(:destroy) }
    end
    context 'for draft records' do
      context 'when not owned by the user' do
        let(:target) { build(:image, :draft, owned_by: "no@no.com") }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:image, :draft, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
    end
    context 'for deleted records' do
      context 'when not owned by the user' do
        let(:target) { build(:image, :deleted, owned_by: "no@no.com") }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:image, :deleted, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
    end
    context 'for private records' do
      context 'when not owned by the user' do
        let(:target) { build(:image, :private, owned_by: "no@no.com") }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
      context 'when owned by the user' do
        let(:target) { build(:image, :private, owned_by: user.email) }
        it { is_expected.to permit_action(:show) }
        it { is_expected.to permit_action(:update) }
        it { is_expected.to permit_action(:destroy) }
      end
    end
  end

  context 'when the user owns the associated record' do
    let(:user) { build(:user, :readwrite) }
    let(:category) { create(:category, owned_by: user.email) }
    context 'when the user does not own the image' do
      let(:target) { build(:image, :private, owned_by: "someone else", imageable: category) }
      it { is_expected.to permit_action(:show) }
      it { is_expected.to permit_action(:update) }
      it { is_expected.to permit_action(:destroy) }
    end
  end
end
