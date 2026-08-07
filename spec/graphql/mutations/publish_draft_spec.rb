# frozen_string_literal: true

require 'rails_helper'

# :versioning is required, not decorative: Drafts::ConflictDetector reads the
# PaperTrail versions of the live row, and PaperTrail is off by default in this
# suite. Without it every conflict example would pass vacuously.
RSpec.describe 'publishDraft', :versioning do
  let(:user) { build(:user, :superadmin) }
  let(:plant) { create(:plant, scientific_name: 'Live', visibility: :public) }
  let(:plant_gid) { PlantApiSchema.id_from_object(plant, Plant, {}) }

  let(:mutation) do
    <<~GRAPHQL
      mutation($input: PublishDraftInput!) {
        publishDraft(input: $input) {
          record {
            ... on Plant { id scientificName familyNames description publicationState accessLevel }
            ... on Category { id name }
            ... on Family { id name description }
          }
          conflictedFields
          errors { code field message }
        }
      }
    GRAPHQL
  end

  def publish(id: plant_gid, force: false, access_level: nil, as: user)
    input = { recordId: id, force: force }
    input[:accessLevel] = access_level if access_level
    PlantApiSchema.execute(mutation, context: { current_user: as },
                                     variables: { input: input })
  end

  def stage(record, data, base: nil)
    create(:record_draft, draftable: record, data: data,
                          base_updated_at: base || record.updated_at)
  end

  describe 'applying the draft' do
    before { stage(plant, { 'scientific_name' => 'Published' }) }

    it 'applies the draft to the live record' do
      publish
      expect(plant.reload.scientific_name).to eq('Published')
    end

    it 'destroys the draft' do
      publish
      expect(plant.reload.record_draft).to be_nil
    end

    it 'returns the published record through the polymorphic payload field' do
      result = publish
      expect(result.dig('data', 'publishDraft', 'record', 'scientificName')).to eq('Published')
    end

    it 'returns no errors' do
      expect(publish.dig('data', 'publishDraft', 'errors')).to be_empty
    end

    it 'writes exactly one version, so history shows what the public saw' do
      expect { publish }.to change { plant.versions.count }.by(1)
    end
  end

  describe 'publication state' do
    it 'publishes a never-published record' do
      plant.update!(visibility: :draft)
      stage(plant, { 'scientific_name' => 'Published' })
      publish
      expect(plant.reload.publication_state).to eq('published')
    end

    it 'applies the requested access level through the dual-write, not by touching visibility' do
      plant.update!(visibility: :draft)
      stage(plant, { 'scientific_name' => 'Published' })
      publish(access_level: 'PUBLIC')
      expect(plant.reload).to have_attributes(access_level: 'public', visibility: 'public')
    end

    it 'leaves an already-published record published' do
      stage(plant, { 'scientific_name' => 'Published' })
      publish
      expect(plant.reload).to have_attributes(publication_state: 'published', visibility: 'public')
    end

    # Family is pure reference data: it has no publication_state, no
    # access_level and no OrganizedResource at all. The flip must be skipped
    # rather than raising NoMethodError.
    it 'publishes a Family, which has no publication state to flip' do
      family = Family.importing { create(:family, name: 'Fabaceae') }
      stage(family, { 'seed_banking_rank' => 3 })
      gid = PlantApiSchema.id_from_object(family, Family, {})

      publish(id: gid)
      expect(family.reload).to have_attributes(seed_banking_rank: 3, record_draft: nil)
    end
  end

  describe 'conflicts' do
    before do
      stage(plant, { 'scientific_name' => 'Published' })
      plant.update!(scientific_name: 'Changed under the draft')
    end

    it 'reports the conflicted field' do
      expect(publish.dig('data', 'publishDraft', 'conflictedFields')).to include('scientific_name')
    end

    it 'refuses to overwrite the live record' do
      publish
      expect(plant.reload.scientific_name).to eq('Changed under the draft')
    end

    it 'keeps the draft so no work is lost' do
      publish
      expect(plant.reload.record_draft).to be_present
    end

    it 'publishes anyway when forced' do
      publish(force: true)
      expect(plant.reload.scientific_name).to eq('Published')
    end

    it 'destroys the draft when forced' do
      publish(force: true)
      expect(plant.reload.record_draft).to be_nil
    end
  end

  describe 'the family_names mirror' do
    # Mutations::Concerns::FamilyAssignment#apply_family is a mutation-layer
    # concern, not a model callback, so publishing has to reproduce it.
    let(:family) { Family.importing { create(:family, name: 'Fabaceae') } }

    it 'fills a blank family_names from the newly assigned family' do
      plant.update!(family_names: nil)
      stage(plant, { 'family_id' => family.id })
      publish
      expect(plant.reload.family_names).to eq('Fabaceae')
    end

    it 'never clobbers family_names a human typed' do
      plant.update!(family_names: 'Bean family, probably')
      stage(plant, { 'family_id' => family.id })
      publish
      expect(plant.reload).to have_attributes(family_names: 'Bean family, probably', family_id: family.id)
    end

    it 'leaves family_names alone when the draft clears the family' do
      plant.update!(family: family, family_names: nil)
      stage(plant, { 'family_id' => nil })
      publish
      expect(plant.reload).to have_attributes(family_id: nil, family_names: nil)
    end
  end

  describe 'translations' do
    it 'publishes a staged translation' do
      stage(plant, { 'translations' => { 'es' => { 'description' => 'Descripcion' } } })
      publish
      expect(plant.reload.translations.dig('es', 'description')).to eq('Descripcion')
    end

    it 'leaves untouched locales intact' do
      stage(plant, { 'translations' => { 'es' => { 'description' => 'Descripcion' } } })
      publish
      expect(plant.reload.translations.dig('en', 'description')).to be_present
    end

    # The empty-container trap: assigning a blob whose leaves are all blank
    # strips to a literal {}, which Type::Serialized writes as SQL NULL against
    # a NOT NULL column. Drafts::Overlay keeps the container savable; the
    # publisher must not defeat that.
    it 'survives a draft that clears the last translated value' do
      bare = create(:plant, scientific_name: 'Bare', visibility: :public,
                            description: 'Only content')
      stage(bare, { 'translations' => { 'en' => { 'description' => nil } } })
      gid = PlantApiSchema.id_from_object(bare, Plant, {})

      result = publish(id: gid)
      expect(result['errors']).to be_nil
      expect(bare.reload.translations).to eq({})
    end
  end

  describe 'failure to persist' do
    # Category validates presence of its translated `name`, so a draft that
    # blanks it is a genuine validation failure reachable through the draftable
    # surface (Plant has no presence validation on any draftable column).
    let(:category) { create(:category, name: 'Live name', visibility: :public) }
    let(:category_gid) { PlantApiSchema.id_from_object(category, Category, {}) }

    before do
      stage(category, { 'translations' => { 'en' => { 'name' => nil, 'description' => nil } } })
    end

    it 'returns the validation errors in the payload' do
      errors = publish(id: category_gid).dig('data', 'publishDraft', 'errors')
      expect(errors.map { |e| e['field'] }).to include('name')
    end

    it 'keeps the draft, because a failed publish must never lose work' do
      publish(id: category_gid)
      expect(category.reload.record_draft).to be_present
    end

    it 'leaves the live record untouched' do
      publish(id: category_gid)
      expect(category.reload.name).to eq('Live name')
    end
  end

  describe 'no-ops' do
    it 'is a no-op, not an error, when the draft changes nothing' do
      stage(plant, {})
      expect(publish.dig('data', 'publishDraft', 'errors')).to be_empty
    end

    it 'destroys an empty draft rather than leaving it behind' do
      stage(plant, {})
      publish
      expect(plant.reload.record_draft).to be_nil
    end

    it 'writes no version when the draft changes nothing' do
      stage(plant, {})
      expect { publish }.not_to(change { plant.versions.count })
    end

    it 'is a no-op when there is no draft at all' do
      result = publish
      expect(result.dig('data', 'publishDraft', 'errors')).to be_empty
      expect(result.dig('data', 'publishDraft', 'record', 'scientificName')).to eq('Live')
    end
  end

  describe 'authorization and lookup' do
    it 'refuses a reader' do
      stage(plant, { 'scientific_name' => 'Published' })
      result = publish(as: build(:user, :readonly))
      expect(result.dig('errors', 0, 'extensions', 'code')).to eq(403)
    end

    it 'leaves the draft alone when the caller is refused' do
      stage(plant, { 'scientific_name' => 'Published' })
      publish(as: build(:user, :readonly))
      expect(plant.reload.record_draft).to be_present
    end

    it '404s on a record type that cannot hold a draft' do
      specimen = create(:specimen)
      gid = PlantApiSchema.id_from_object(specimen, Specimen, {})
      result = publish(id: gid)
      expect(result.dig('errors', 0, 'extensions', 'code')).to eq(404)
    end

    it '404s on a malformed global id' do
      result = publish(id: 'not-a-global-id')
      expect(result.dig('errors', 0, 'extensions', 'code')).to eq(404)
    end
  end
end
