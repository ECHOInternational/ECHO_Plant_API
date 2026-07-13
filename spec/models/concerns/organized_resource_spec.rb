# frozen_string_literal: true

require 'rails_helper'

# Plant is used as the canonical host for OrganizedResource tests because it
# has the full ownership column set. All behaviours apply equally to Variety,
# Specimen, Location, and Category.
RSpec.describe OrganizedResource, type: :model do
  subject(:plant) { build(:plant, visibility: :private) }

  describe 'create path (legacy): populates trio from default visibility' do
    it 'sets publication_state to published and access_level to organization for private' do
      p = create(:plant, visibility: :private)
      expect(p.publication_state).to eq 'published'
      expect(p.access_level).to eq 'organization'
      expect(p.deleted_at).to be_nil
    end

    it 'sets published/public for :public visibility' do
      p = create(:plant, visibility: :public)
      expect(p.publication_state).to eq 'published'
      expect(p.access_level).to eq 'public'
    end

    it 'sets draft/organization for :draft visibility' do
      p = create(:plant, visibility: :draft)
      expect(p.publication_state).to eq 'draft'
      expect(p.access_level).to eq 'organization'
    end
  end

  describe 'legacy-API soft-delete (visibility: :deleted)' do
    let!(:plant) { create(:plant, visibility: :private) }

    it 'sets deleted_at and preserves the prior trio' do
      plant.update!(visibility: :deleted)
      expect(plant.deleted_at).to be_present
      expect(plant.publication_state).to eq 'published'
      expect(plant.access_level).to eq 'organization'
    end

    it 'captures trio from prior visibility when trio was nil' do
      # Simulate a pre-backfill row that has no trio set
      plant.update_columns(publication_state: nil, access_level: nil)
      plant.reload
      plant.visibility = :deleted
      plant.save!
      expect(plant.publication_state).to eq 'published'
      expect(plant.access_level).to eq 'organization'
    end
  end

  describe 'legacy-API restore (visibility: :private after deleted)' do
    let!(:plant) do
      p = create(:plant, visibility: :public)
      p.update!(visibility: :deleted)
      p
    end

    it 'clears deleted_at on restore' do
      plant.update!(visibility: :private)
      expect(plant.deleted_at).to be_nil
    end

    it 'sets published/organization trio' do
      plant.update!(visibility: :private)
      expect(plant.publication_state).to eq 'published'
      expect(plant.access_level).to eq 'organization'
    end
  end

  describe 'new-API path: publication_state/access_level change recomputes visibility' do
    let!(:plant) { create(:plant, visibility: :private) }

    it 'sets visibility to public when published + public' do
      plant.publication_state = 'published'
      plant.access_level      = 'public'
      plant.save!
      expect(plant.visibility).to eq 'public'
    end

    it 'sets visibility to draft when draft' do
      plant.publication_state = 'draft'
      plant.save!
      expect(plant.visibility).to eq 'draft'
    end

    it 'sets visibility to deleted when deleted_at is set' do
      plant.deleted_at = Time.current
      plant.save!
      expect(plant.visibility).to eq 'deleted'
    end
  end

  describe 'precedence: new-API changes take priority in same save' do
    let!(:plant) { create(:plant, visibility: :private) }

    it 'follows new-API (precedence a) when both change' do
      plant.visibility        = :public    # legacy change
      plant.publication_state = 'draft'    # new-API change -- wins
      plant.access_level      = 'organization'
      plant.save!
      expect(plant.visibility).to eq 'draft'
    end
  end

  describe 'nil trio with deleted visibility (pre-backfill row shape)' do
    it 'maps to :deleted' do
      derived = VisibilityBridge.visibility_for(
        publication_state: nil,
        access_level: nil,
        deleted_at: Time.current
      )
      expect(derived).to eq :deleted
    end

    it 'maps to :private when all nil (legacy un-backfilled)' do
      derived = VisibilityBridge.visibility_for(
        publication_state: nil,
        access_level: nil,
        deleted_at: nil
      )
      expect(derived).to eq :private
    end
  end
end
