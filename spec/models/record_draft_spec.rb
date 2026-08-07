# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RecordDraft do
  let(:plant) { create(:plant) }
  # RecordDraft requires author_principal_id/last_editor_principal_id (NOT
  # NULL + FK in the migration, required `belongs_to` on the model), so every
  # create! below must supply them.
  let(:principal) { create(:principal) }

  # This is the whole reason drafts are not stored in PaperTrail. If a draft
  # save writes a version, the recordHistory drawer fills with edits that never
  # happened to the live record. ApplicationRecord calls has_paper_trail
  # unconditionally, so the opt-out is easy to lose in a refactor and silent
  # when lost.
  it 'writes no PaperTrail versions' do
    expect {
      draft = described_class.create!(draftable: plant, data: { 'scientific_name' => 'X' },
                                      base_updated_at: plant.updated_at,
                                      author_principal_id: principal.id,
                                      last_editor_principal_id: principal.id)
      draft.update!(data: { 'scientific_name' => 'Y' })
      draft.destroy!
    }.not_to change { PaperTrail::Version.where(item_type: 'RecordDraft').count }.from(0)
  end

  it 'allows only one draft per record' do
    described_class.create!(draftable: plant, data: {}, base_updated_at: plant.updated_at,
                            author_principal_id: principal.id, last_editor_principal_id: principal.id)
    expect {
      described_class.create!(draftable: plant, data: {}, base_updated_at: plant.updated_at,
                              author_principal_id: principal.id, last_editor_principal_id: principal.id)
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'allows drafts on different records of the same type' do
    other = create(:plant)
    described_class.create!(draftable: plant, data: {}, base_updated_at: plant.updated_at,
                            author_principal_id: principal.id, last_editor_principal_id: principal.id)
    expect {
      described_class.create!(draftable: other, data: {}, base_updated_at: other.updated_at,
                              author_principal_id: principal.id, last_editor_principal_id: principal.id)
    }.not_to raise_error
  end
end
