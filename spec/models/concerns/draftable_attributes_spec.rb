# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DraftableAttributes do
  it 'includes family_id for Plant' do
    # Regression: families landed after record-history and the restore
    # whitelist was never extended, so restoring a version silently left the
    # family assignment untouched. One shared constant prevents a repeat.
    expect(described_class.for(Plant)).to include('family_id')
  end

  it 'includes translations for every draftable model' do
    [Plant, Variety, Family, Category].each do |model|
      expect(described_class.for(model)).to include('translations')
    end
  end

  it 'never includes ownership or workflow columns' do
    forbidden = %w[id visibility publication_state access_level deleted_at owned_by created_by
                   owner_organization_id created_by_principal_id]
    [Plant, Variety, Family, Category].each do |model|
      expect(described_class.for(model) & forbidden).to be_empty
    end
  end
end
