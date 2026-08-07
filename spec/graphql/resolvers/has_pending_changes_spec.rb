# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'plants(hasPendingChanges:)' do
  let(:user) { build(:user, trust_level: 10) }
  let!(:with_draft) { create(:plant, visibility: :public) }
  let!(:without_draft) { create(:plant, visibility: :public) }

  before { create(:record_draft, draftable: with_draft, base_updated_at: with_draft.updated_at) }

  def ids(value)
    result = PlantApiSchema.execute(
      'query($v: Boolean) { plants(hasPendingChanges: $v) { edges { node { uuid } } } }',
      context: { current_user: user }, variables: { v: value }
    )
    result.dig('data', 'plants', 'edges').map { |e| e.dig('node', 'uuid') }
  end

  it 'returns only records with a pending draft when true' do
    expect(ids(true)).to contain_exactly(with_draft.id)
  end

  it 'returns only records without one when false' do
    expect(ids(false)).to include(without_draft.id)
    expect(ids(false)).not_to include(with_draft.id)
  end

  it 'returns everything when the filter is absent' do
    expect(ids(nil)).to include(with_draft.id, without_draft.id)
  end
end

RSpec.describe 'varieties(hasPendingChanges:)' do
  let(:user) { build(:user, trust_level: 10) }
  let!(:with_draft) { create(:variety, visibility: :public) }
  let!(:without_draft) { create(:variety, visibility: :public) }

  before { create(:record_draft, draftable: with_draft, base_updated_at: with_draft.updated_at) }

  def ids(value)
    result = PlantApiSchema.execute(
      'query($v: Boolean) { varieties(hasPendingChanges: $v) { edges { node { uuid } } } }',
      context: { current_user: user }, variables: { v: value }
    )
    result.dig('data', 'varieties', 'edges').map { |e| e.dig('node', 'uuid') }
  end

  it 'returns only records with a pending draft when true' do
    expect(ids(true)).to contain_exactly(with_draft.id)
  end

  it 'returns only records without one when false' do
    expect(ids(false)).to include(without_draft.id)
    expect(ids(false)).not_to include(with_draft.id)
  end

  it 'returns everything when the filter is absent' do
    expect(ids(nil)).to include(with_draft.id, without_draft.id)
  end
end

RSpec.describe 'categories(hasPendingChanges:)' do
  let(:user) { build(:user, trust_level: 10) }
  let!(:with_draft) { create(:category, visibility: :public) }
  let!(:without_draft) { create(:category, visibility: :public) }

  before { create(:record_draft, draftable: with_draft, base_updated_at: with_draft.updated_at) }

  def ids(value)
    result = PlantApiSchema.execute(
      'query($v: Boolean) { categories(hasPendingChanges: $v) { edges { node { uuid } } } }',
      context: { current_user: user }, variables: { v: value }
    )
    result.dig('data', 'categories', 'edges').map { |e| e.dig('node', 'uuid') }
  end

  it 'returns only records with a pending draft when true' do
    expect(ids(true)).to contain_exactly(with_draft.id)
  end

  it 'returns only records without one when false' do
    expect(ids(false)).to include(without_draft.id)
    expect(ids(false)).not_to include(with_draft.id)
  end

  it 'returns everything when the filter is absent' do
    expect(ids(nil)).to include(with_draft.id, without_draft.id)
  end
end

RSpec.describe 'families(hasPendingChanges:)' do
  let(:user) { build(:user, trust_level: 10) }
  let!(:with_draft) { Family.importing { create(:family) } }
  let!(:without_draft) { Family.importing { create(:family) } }

  before { create(:record_draft, draftable: with_draft, base_updated_at: with_draft.updated_at) }

  def ids(value)
    result = PlantApiSchema.execute(
      'query($v: Boolean) { families(hasPendingChanges: $v) { edges { node { uuid } } } }',
      context: { current_user: user }, variables: { v: value }
    )
    result.dig('data', 'families', 'edges').map { |e| e.dig('node', 'uuid') }
  end

  it 'returns only records with a pending draft when true' do
    expect(ids(true)).to contain_exactly(with_draft.id)
  end

  it 'returns only records without one when false' do
    expect(ids(false)).to include(without_draft.id)
    expect(ids(false)).not_to include(with_draft.id)
  end

  it 'returns everything when the filter is absent' do
    expect(ids(nil)).to include(with_draft.id, without_draft.id)
  end
end
