# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Common name mutations', type: :graphql_mutation do
  let(:current_user) { build(:user, :readwrite) }
  let!(:plant) { create(:plant, owned_by: current_user.email, created_by: current_user.email) }
  let(:plant_gid) { PlantApiSchema.id_from_object(plant, Plant, {}) }

  def execute(query, input)
    PlantApiSchema.execute(query, context: { current_user: current_user }, variables: { input: input })
  end

  describe 'addCommonName' do
    let(:query) do
      <<-GRAPHQL
        mutation($input: AddCommonNameInput!){
          addCommonName(input: $input){
            errors { field message code }
            commonName { uuid name language location primary }
          }
        }
      GRAPHQL
    end

    it 'adds a non-primary name, upcasing the language' do
      result = execute(query, { plantId: plant_gid, name: 'Velvet bean', language: 'en' })
      cn = result['data']['addCommonName']['commonName']
      expect(cn['name']).to eq 'Velvet bean'
      expect(cn['language']).to eq 'EN'
      expect(cn['primary']).to be false
    end

    it 'demotes the existing primary when adding a new primary' do
      existing = create(:common_name, plant: plant, language: 'EN', primary: true)
      execute(query, { plantId: plant_gid, name: 'Mucuna', language: 'en', primary: true })
      expect(existing.reload.primary).to be false
      expect(plant.common_names.where(language: 'EN', primary: true).count).to eq 1
    end

    it 'rejects non-owners with 403' do
      result = PlantApiSchema.execute(query, context: { current_user: build(:user, :readwrite) },
                                             variables: { input: { plantId: plant_gid, name: 'X', language: 'en' } })
      expect(result['errors'][0]['extensions']['code']).to eq 403
    end

    it 'returns a payload error for a blank name' do
      result = execute(query, { plantId: plant_gid, name: '', language: 'en' })
      expect(result['data']['addCommonName']['errors'][0]['field']).to eq 'name'
    end

    it 'preserves existing primary when adding a new primary with invalid name fails' do
      # Create an existing primary for this language
      existing_primary = create(:common_name, plant: plant, language: 'EN', primary: true, name: 'Original')

      # Try to add a primary with blank name (invalid)
      result = execute(query, { plantId: plant_gid, name: '', language: 'en', primary: true })

      # Should have errors and no common_name returned
      expect(result['data']['addCommonName']['errors'][0]['field']).to eq 'name'
      expect(result['data']['addCommonName']['commonName']).to be nil

      # Existing primary should still be primary (demotion rolled back)
      expect(existing_primary.reload.primary).to be true
      expect(plant.common_names.where(language: 'EN', primary: true).count).to eq 1
    end
  end

  describe 'updateCommonName / deleteCommonName / setPrimaryCommonName' do
    let!(:common_name) { create(:common_name, plant: plant, language: 'EN', primary: false) }
    let(:cn_gid) { PlantApiSchema.id_from_object(common_name, CommonName, {}) }

    it 'updates name and location' do
      query = 'mutation($input: UpdateCommonNameInput!){ updateCommonName(input: $input){ commonName { name location } errors { message } } }'
      result = execute(query, { commonNameId: cn_gid, name: 'Lablab', location: 'East Africa' })
      cn = result['data']['updateCommonName']['commonName']
      expect(cn['name']).to eq 'Lablab'
      expect(cn['location']).to eq 'East Africa'
    end

    it 'deletes and returns the id' do
      query = 'mutation($input: DeleteCommonNameInput!){ deleteCommonName(input: $input){ commonNameId errors { message } } }'
      result = execute(query, { commonNameId: cn_gid })
      expect(result['data']['deleteCommonName']['commonNameId']).to eq cn_gid
      expect(CommonName.exists?(common_name.id)).to be false
    end

    it 'setPrimary promotes and demotes within the language' do
      other_primary = create(:common_name, plant: plant, language: 'EN', primary: true)
      query = 'mutation($input: SetPrimaryCommonNameInput!){ setPrimaryCommonName(input: $input){ commonName { primary } errors { message } } }'
      result = execute(query, { commonNameId: cn_gid })
      expect(result['data']['setPrimaryCommonName']['commonName']['primary']).to be true
      expect(other_primary.reload.primary).to be false
    end

    it 'authorizes against the parent plant' do
      query = 'mutation($input: DeleteCommonNameInput!){ deleteCommonName(input: $input){ commonNameId } }'
      result = PlantApiSchema.execute(query, context: { current_user: build(:user, :readwrite) },
                                             variables: { input: { commonNameId: cn_gid } })
      expect(result['errors'][0]['extensions']['code']).to eq 403
    end
  end
end
