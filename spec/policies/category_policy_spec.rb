require 'rails_helper'

RSpec.describe CategoryPolicy do

  subject { described_class.new(user, category) }

  context 'when no user logged in' do
  	let(:user) { nil }

  	let (:category) { Category }
  	it { is_expected.to forbid_action(:create)}

  	context 'for public records' do
  		let(:category) { build(:category, :public) }
  		it { is_expected.to permit_action(:show) }
  		it { is_expected.to forbid_action(:update) }
  		it { is_expected.to forbid_action(:destroy) }
  	end
  	context 'for draft records' do
  		let(:category) { build(:category, :draft) }
  		it { is_expected.to forbid_action(:show) }
  		it { is_expected.to forbid_action(:update) }
  		it { is_expected.to forbid_action(:destroy) }
  	end
  	context 'for deleted records' do
  		let(:category) { build(:category, :deleted) }
  		it { is_expected.to forbid_action(:show) }
  		it { is_expected.to forbid_action(:update) }
  		it { is_expected.to forbid_action(:destroy) }
  	end
  	context 'for private records' do
  		let(:category) { build(:category, :private) }
  		it { is_expected.to forbid_action(:show) }
  		it { is_expected.to forbid_action(:update) }
  		it { is_expected.to forbid_action(:destroy) }
  	end
  end

  context 'when user has read-only accesss' do
  	let(:user) { build(:user, :readonly) }

  	let (:category) { Category }
  	it { is_expected.to forbid_action(:create)}

  	context 'for public records' do
  		let(:category) { build(:category, :public) }
  		it { is_expected.to permit_action(:show) }
  		it { is_expected.to forbid_action(:update) }
  		it { is_expected.to forbid_action(:destroy) }
  	end
  	context 'for draft records' do
  		context 'when not owned by the user' do
	  		let(:category) { build(:category, :draft, owned_by: "no@no.com") }
	  		it { is_expected.to forbid_action(:show) }
	  		it { is_expected.to forbid_action(:update) }
	  		it { is_expected.to forbid_action(:destroy) }
	  	end
	  	context 'when owned by the user' do
	  		let(:category) { build(:category, :draft, owned_by: user.email) }
	  		it { is_expected.to permit_action(:show) }
	  		it { is_expected.to forbid_action(:update) }
	  		it { is_expected.to forbid_action(:destroy) }
	  	end
  	end
  	context 'for deleted records' do
  		context 'when not owned by the user' do
	  		let(:category) { build(:category, :deleted, owned_by: "no@no.com") }
	  		it { is_expected.to forbid_action(:show) }
	  		it { is_expected.to forbid_action(:update) }
	  		it { is_expected.to forbid_action(:destroy) }
	  	end
	  	context 'when owned by the user' do
	  		let(:category) { build(:category, :deleted, owned_by: user.email) }
	  		it { is_expected.to permit_action(:show) }
	  		it { is_expected.to forbid_action(:update) }
	  		it { is_expected.to forbid_action(:destroy) }
	  	end
  	end
  	context 'for private records' do
  		context 'when not owned by the user' do
	  		let(:category) { build(:category, :private, owned_by: "no@no.com") }
	  		it { is_expected.to forbid_action(:show) }
	  		it { is_expected.to forbid_action(:update) }
	  		it { is_expected.to forbid_action(:destroy) }
	  	end
	  	context 'when owned by the user' do
	  		let(:category) { build(:category, :private, owned_by: user.email) }
	  		it { is_expected.to permit_action(:show) }
	  		it { is_expected.to forbid_action(:update) }
	  		it { is_expected.to forbid_action(:destroy) }
	  	end
  	end
  end

  context 'when user has write accesss' do
  	let(:user) { build(:user, :readwrite) }

  	let (:category) { Category }
  	it { is_expected.to permit_action(:create)}

  	context 'for public records' do
  		let(:category) { build(:category, :public) }
  		it { is_expected.to permit_action(:show) }
  		it { is_expected.to forbid_action(:update) }
  		it { is_expected.to forbid_action(:destroy) }
  	end
  	context 'for draft records' do
  		context 'when not owned by the user' do
	  		let(:category) { build(:category, :draft, owned_by: "no@no.com") }
	  		it { is_expected.to forbid_action(:show) }
	  		it { is_expected.to forbid_action(:update) }
	  		it { is_expected.to forbid_action(:destroy) }
	  	end
	  	context 'when owned by the user' do
	  		let(:category) { build(:category, :draft, owned_by: user.email) }
	  		it { is_expected.to permit_action(:show) }
	  		it { is_expected.to permit_action(:update) }
	  		it { is_expected.to permit_action(:destroy) }
	  	end
  	end
  	context 'for deleted records' do
  		context 'when not owned by the user' do
	  		let(:category) { build(:category, :deleted, owned_by: "no@no.com") }
	  		it { is_expected.to forbid_action(:show) }
	  		it { is_expected.to forbid_action(:update) }
	  		it { is_expected.to forbid_action(:destroy) }
	  	end
	  	context 'when owned by the user' do
	  		let(:category) { build(:category, :deleted, owned_by: user.email) }
	  		it { is_expected.to permit_action(:show) }
	  		it { is_expected.to permit_action(:update) }
	  		it { is_expected.to permit_action(:destroy) }
	  	end
  	end
  	context 'for private records' do
  		context 'when not owned by the user' do
	  		let(:category) { build(:category, :private, owned_by: "no@no.com") }
	  		it { is_expected.to forbid_action(:show) }
	  		it { is_expected.to forbid_action(:update) }
	  		it { is_expected.to forbid_action(:destroy) }
	  	end
	  	context 'when owned by the user' do
	  		let(:category) { build(:category, :private, owned_by: user.email) }
	  		it { is_expected.to permit_action(:show) }
	  		it { is_expected.to permit_action(:update) }
	  		it { is_expected.to permit_action(:destroy) }
	  	end
  	end
  end

  context 'when user is admin' do
  	let(:user) { build(:user, :admin) }

  	let (:category) { Category }
  	it { is_expected.to permit_action(:create)}

  	context 'for public records' do
  		let(:category) { build(:category, :public) }
  		it { is_expected.to permit_action(:show) }
  		it { is_expected.to permit_action(:update) }
  		it { is_expected.to forbid_action(:destroy) }
  	end
  	context 'for draft records' do
  		context 'when not owned by the user' do
	  		let(:category) { build(:category, :draft, owned_by: "no@no.com") }
	  		it { is_expected.to permit_action(:show) }
	  		it { is_expected.to permit_action(:update) }
	  		it { is_expected.to forbid_action(:destroy) }
	  	end
	  	context 'when owned by the user' do
	  		let(:category) { build(:category, :draft, owned_by: user.email) }
	  		it { is_expected.to permit_action(:show) }
	  		it { is_expected.to permit_action(:update) }
	  		it { is_expected.to permit_action(:destroy) }
	  	end
  	end
  	context 'for deleted records' do
  		context 'when not owned by the user' do
	  		let(:category) { build(:category, :deleted, owned_by: "no@no.com") }
	  		it { is_expected.to permit_action(:show) }
	  		it { is_expected.to permit_action(:update) }
	  		it { is_expected.to forbid_action(:destroy) }
	  	end
	  	context 'when owned by the user' do
	  		let(:category) { build(:category, :deleted, owned_by: user.email) }
	  		it { is_expected.to permit_action(:show) }
	  		it { is_expected.to permit_action(:update) }
	  		it { is_expected.to permit_action(:destroy) }
	  	end
  	end
  	context 'for private records' do
  		context 'when not owned by the user' do
	  		let(:category) { build(:category, :private, owned_by: "no@no.com") }
	  		it { is_expected.to permit_action(:show) }
	  		it { is_expected.to permit_action(:update) }
	  		it { is_expected.to forbid_action(:destroy) }
	  	end
	  	context 'when owned by the user' do
	  		let(:category) { build(:category, :private, owned_by: user.email) }
	  		it { is_expected.to permit_action(:show) }
	  		it { is_expected.to permit_action(:update) }
	  		it { is_expected.to permit_action(:destroy) }
	  	end
  	end
  end

  context 'when user is super admin' do
  	let(:user) { build(:user, :superadmin) }

  	let (:category) { Category }
  	it { is_expected.to permit_action(:create)}

  	context 'for public records' do
  		let(:category) { build(:category, :public) }
  		it { is_expected.to permit_action(:show) }
  		it { is_expected.to permit_action(:update) }
  		it { is_expected.to permit_action(:destroy) }
  	end
  	context 'for draft records' do
  		context 'when not owned by the user' do
	  		let(:category) { build(:category, :draft, owned_by: "no@no.com") }
	  		it { is_expected.to permit_action(:show) }
	  		it { is_expected.to permit_action(:update) }
	  		it { is_expected.to permit_action(:destroy) }
	  	end
	  	context 'when owned by the user' do
	  		let(:category) { build(:category, :draft, owned_by: user.email) }
	  		it { is_expected.to permit_action(:show) }
	  		it { is_expected.to permit_action(:update) }
	  		it { is_expected.to permit_action(:destroy) }
	  	end
  	end
  	context 'for deleted records' do
  		context 'when not owned by the user' do
	  		let(:category) { build(:category, :deleted, owned_by: "no@no.com") }
	  		it { is_expected.to permit_action(:show) }
	  		it { is_expected.to permit_action(:update) }
	  		it { is_expected.to permit_action(:destroy) }
	  	end
	  	context 'when owned by the user' do
	  		let(:category) { build(:category, :deleted, owned_by: user.email) }
	  		it { is_expected.to permit_action(:show) }
	  		it { is_expected.to permit_action(:update) }
	  		it { is_expected.to permit_action(:destroy) }
	  	end
  	end
  	context 'for private records' do
  		context 'when not owned by the user' do
	  		let(:category) { build(:category, :private, owned_by: "no@no.com") }
	  		it { is_expected.to permit_action(:show) }
	  		it { is_expected.to permit_action(:update) }
	  		it { is_expected.to permit_action(:destroy) }
	  	end
	  	context 'when owned by the user' do
	  		let(:category) { build(:category, :private, owned_by: user.email) }
	  		it { is_expected.to permit_action(:show) }
	  		it { is_expected.to permit_action(:update) }
	  		it { is_expected.to permit_action(:destroy) }
	  	end
  	end
  end


end