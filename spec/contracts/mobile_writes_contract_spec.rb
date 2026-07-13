# frozen_string_literal: true

require 'rails_helper'

# Contract: write mutations used by the frozen React Native mobile app.
# Source documents extracted verbatim from:
#   app/store/SeedTrialReports/action.js
#   app/store/Plants/action.js
#   app/screens/MyPlants/index.js
#   app/screens/MyVariety/index.js
#   app/screens/MyLocations/index.js
#
# All mutations use a trust-level-2 (readwrite) user, which is the normal
# authenticated user on the mobile app. The response shapes asserted here
# are exactly what the app reads off the result.
RSpec.describe 'Mobile writes contract', type: :graphql_mutation do
  let(:user) { build(:user, :readwrite) }

  # -----------------------------------------------------------------
  # createSpecimen -- createSeedTrialReport
  # -----------------------------------------------------------------
  describe 'createSpecimen (SeedTrialReports/action.js createSeedTrialReport)' do
    let(:plant) { create(:plant, :public) }
    let(:variety) { create(:variety, :public, plant: plant) }

    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: CreateSpecimenInput!) {
          createSpecimen(input: $input) {
            clientMutationId
            specimen {
              id
              name
              plant {
                id
                primaryCommonName
                scientificName
              }
              variety {
                id
                name
              }
            }
          }
        }
      GRAPHQL
    end

    it 'creates a specimen and returns the app-required shape' do
      plant_id   = PlantApiSchema.id_from_object(plant, Plant, {})
      variety_id = PlantApiSchema.id_from_object(variety, Variety, {})
      result = PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: {
          input: {
            name: 'Trial Specimen',
            plantId: plant_id,
            varietyId: variety_id
          }
        }
      )
      expect(result['errors']).to be_nil
      spec_result = result.dig('data', 'createSpecimen', 'specimen')
      expect(spec_result['id']).to be_present
      expect(spec_result['name']).to eq('Trial Specimen')
      expect(spec_result.dig('plant', 'id')).to eq(plant_id)
      expect(spec_result.dig('variety', 'id')).to eq(variety_id)
    end
  end

  # -----------------------------------------------------------------
  # updateSpecimen -- updateSeedTrialReport (normal update)
  # -----------------------------------------------------------------
  describe 'updateSpecimen (SeedTrialReports/action.js updateSeedTrialReport)' do
    let(:specimen) { create(:specimen, owned_by: user.email, created_by: user.email) }

    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: UpdateSpecimenInput!) {
          updateSpecimen(input: $input) {
            clientMutationId
            specimen {
              id
              name
              plant {
                id
                primaryCommonName
                scientificName
              }
              variety {
                id
                name
              }
            }
          }
        }
      GRAPHQL
    end

    it 'updates and returns the app-required shape' do
      spec_id = PlantApiSchema.id_from_object(specimen, Specimen, {})
      result = PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: { input: { specimenId: spec_id, notes: 'Updated notes' } }
      )
      expect(result['errors']).to be_nil
      spec_result = result.dig('data', 'updateSpecimen', 'specimen')
      expect(spec_result['id']).to eq(spec_id)
    end
  end

  # -----------------------------------------------------------------
  # updateSpecimen with visibility: DELETED -- specimen delete path
  # The app uses updateSpecimen(input: { specimenId: ..., visibility: DELETED })
  # as its soft-delete path (SeedTrialReports/action.js deleteSpecimenFromServer).
  # -----------------------------------------------------------------
  describe 'updateSpecimen visibility DELETED (deleteSpecimenFromServer)' do
    let(:specimen) { create(:specimen, owned_by: user.email, created_by: user.email) }

    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: UpdateSpecimenInput!) {
          updateSpecimen(input: $input) {
            clientMutationId
            specimen {
              id
              visibility
            }
          }
        }
      GRAPHQL
    end

    it 'marks the specimen as DELETED' do
      spec_id = PlantApiSchema.id_from_object(specimen, Specimen, {})
      result = PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: { input: { specimenId: spec_id, visibility: 'DELETED' } }
      )
      expect(result['errors']).to be_nil
      spec_result = result.dig('data', 'updateSpecimen', 'specimen')
      expect(spec_result['visibility']).to eq('DELETED')
      expect(Specimen.find(specimen.id).visibility_deleted?).to be true
    end
  end

  # -----------------------------------------------------------------
  # evaluateSpecimen -- addEvaluateTheCropToSeedTrialReport
  # -----------------------------------------------------------------
  describe 'evaluateSpecimen (SeedTrialReports/action.js addEvaluateTheCropToSeedTrialReport)' do
    let(:specimen) { create(:specimen, owned_by: user.email, created_by: user.email) }

    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: EvaluateSpecimenInput!) {
          evaluateSpecimen(input: $input) {
            clientMutationId
            specimen {
              id
              name
              notes
            }
          }
        }
      GRAPHQL
    end

    it 'evaluates specimen and returns app-required shape' do
      spec_id = PlantApiSchema.id_from_object(specimen, Specimen, {})
      result = PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: {
          input: {
            specimenId: spec_id,
            successful: true,
            recommended: true,
            savedSeed: false,
            willShareSeed: true,
            willPlantAgain: true
          }
        }
      )
      expect(result['errors']).to be_nil
      spec_result = result.dig('data', 'evaluateSpecimen', 'specimen')
      expect(spec_result['id']).to eq(spec_id)
    end
  end

  # -----------------------------------------------------------------
  # createPlant -- addCustomPlant
  # -----------------------------------------------------------------
  describe 'createPlant (SeedTrialReports/action.js addCustomPlant)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: CreatePlantInput!) {
          createPlant(input: $input) {
            plant {
              id
              primaryCommonName
              scientificName
              description
              createdBy
              createdAt
              updatedAt
              ownedBy
              familyNames
            }
            clientMutationId
            errors {
              code
              field
              message
              value
            }
          }
        }
      GRAPHQL
    end

    it 'creates and returns every field the app reads' do
      result = PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: {
          input: {
            primaryCommonName: 'Custom Moringa',
            scientificName: 'Moringa oleifera',
            language: 'en'
          }
        }
      )
      expect(result['errors']).to be_nil
      plant_result = result.dig('data', 'createPlant', 'plant')
      expect(plant_result['id']).to be_present
      expect(plant_result['primaryCommonName']).to eq('Custom Moringa')
      expect(plant_result['ownedBy']).to eq(user.email)
      expect(plant_result['createdBy']).to eq(user.email)
      errors = result.dig('data', 'createPlant', 'errors')
      expect(errors).to be_an(Array)
    end
  end

  # -----------------------------------------------------------------
  # updatePlant -- updateCustomPlant
  # -----------------------------------------------------------------
  describe 'updatePlant (SeedTrialReports/action.js updateCustomPlant)' do
    let(:plant) { create(:plant, :private, owned_by: user.email, created_by: user.email) }

    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: UpdatePlantInput!) {
          updatePlant(input: $input) {
            plant {
              id
              primaryCommonName
              scientificName
              description
              createdBy
              createdAt
              updatedAt
              ownedBy
              familyNames
            }
            clientMutationId
            errors {
              code
              field
              message
              value
            }
          }
        }
      GRAPHQL
    end

    it 'updates and returns the app-required shape including ownership' do
      plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
      result = PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: {
          input: {
            plantId: plant_id,
            primaryCommonName: 'Updated Moringa',
            language: 'en'
          }
        }
      )
      expect(result['errors']).to be_nil
      plant_result = result.dig('data', 'updatePlant', 'plant')
      expect(plant_result['id']).to eq(plant_id)
      expect(plant_result['ownedBy']).to be_a(String)
      expect(result.dig('data', 'updatePlant', 'errors')).to be_an(Array)
    end
  end

  # -----------------------------------------------------------------
  # createVariety -- addCustomVariety
  # -----------------------------------------------------------------
  describe 'createVariety (SeedTrialReports/action.js addCustomVariety)' do
    let(:plant) { create(:plant, :public) }

    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: CreateVarietyInput!) {
          createVariety(input: $input) {
            variety {
              id
              name
              description
              createdBy
              createdAt
              updatedAt
              ownedBy
              plant {
                id
                primaryCommonName
                scientificName
                description
                createdBy
                createdAt
                updatedAt
                ownedBy
                familyNames
              }
            }
            clientMutationId
            errors {
              code
              field
              message
              value
            }
          }
        }
      GRAPHQL
    end

    it 'creates variety with nested plant fields the app depends on' do
      plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
      result = PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: {
          input: {
            plantId: plant_id,
            name: 'Red Variety',
            language: 'en'
          }
        }
      )
      expect(result['errors']).to be_nil
      variety_result = result.dig('data', 'createVariety', 'variety')
      expect(variety_result['id']).to be_present
      expect(variety_result['ownedBy']).to eq(user.email)
      expect(variety_result.dig('plant', 'id')).to eq(plant_id)
      expect(variety_result.dig('plant', 'familyNames')).not_to be_nil
    end
  end

  # -----------------------------------------------------------------
  # updateVariety -- updateCustomVariety
  # -----------------------------------------------------------------
  describe 'updateVariety (SeedTrialReports/action.js updateCustomVariety)' do
    let(:plant) { create(:plant, :public) }
    let(:variety) { create(:variety, :private, plant: plant, owned_by: user.email, created_by: user.email) }

    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: UpdateVarietyInput!) {
          updateVariety(input: $input) {
            variety {
              id
              name
              description
              createdBy
              createdAt
              updatedAt
              ownedBy
              plant {
                id
                primaryCommonName
                scientificName
                description
                createdBy
                createdAt
                updatedAt
                ownedBy
                familyNames
              }
            }
            clientMutationId
            errors {
              code
              field
              message
              value
            }
          }
        }
      GRAPHQL
    end

    it 'updates variety and returns nested plant ownership fields' do
      variety_id = PlantApiSchema.id_from_object(variety, Variety, {})
      result = PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: {
          input: {
            varietyId: variety_id,
            name: 'Updated Red Variety',
            language: 'en'
          }
        }
      )
      expect(result['errors']).to be_nil
      variety_result = result.dig('data', 'updateVariety', 'variety')
      expect(variety_result['id']).to eq(variety_id)
      expect(variety_result.dig('plant', 'ownedBy')).to be_a(String)
    end
  end

  # -----------------------------------------------------------------
  # createLocation -- addLocationToSpecimen
  # -----------------------------------------------------------------
  describe 'createLocation (SeedTrialReports/action.js addLocationToSpecimen)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: CreateLocationInput!) {
          createLocation(input: $input) {
            location {
              id
              name
              altitude
              irrigated
              latitude
              longitude
              ownedBy
              slope
              soilQuality
              visibility
            }
            clientMutationId
            errors {
              code
              field
              message
              value
            }
          }
        }
      GRAPHQL
    end

    it 'creates and returns every field the app reads off createLocation' do
      result = PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: {
          input: {
            name: 'Test Field',
            soilQuality: 'GOOD',
            slope: 5,
            altitude: 100,
            irrigated: true,
            latitude: 14.5,
            longitude: -89.2
          }
        }
      )
      expect(result['errors']).to be_nil
      loc_result = result.dig('data', 'createLocation', 'location')
      %w[id name altitude irrigated latitude longitude ownedBy slope soilQuality visibility].each do |f|
        expect(loc_result).to have_key(f), "expected '#{f}' in createLocation response"
      end
      expect(loc_result['ownedBy']).to eq(user.email)
    end
  end

  # -----------------------------------------------------------------
  # updateLocation -- updateLocationToSpecimen
  # -----------------------------------------------------------------
  describe 'updateLocation (SeedTrialReports/action.js updateLocationToSpecimen)' do
    let(:location) { create(:location, owned_by: user.email, created_by: user.email) }

    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: UpdateLocationInput!) {
          updateLocation(input: $input) {
            location {
              id
              name
              altitude
              irrigated
              latitude
              longitude
              ownedBy
              slope
              soilQuality
              visibility
            }
            clientMutationId
            errors {
              code
              field
              message
              value
            }
          }
        }
      GRAPHQL
    end

    it 'updates and returns all fields the app reads' do
      loc_id = PlantApiSchema.id_from_object(location, Location, {})
      result = PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: { input: { locationId: loc_id, name: 'Updated Field' } }
      )
      expect(result['errors']).to be_nil
      loc_result = result.dig('data', 'updateLocation', 'location')
      expect(loc_result['id']).to eq(loc_id)
      %w[id name altitude irrigated latitude longitude ownedBy slope soilQuality visibility].each do |f|
        expect(loc_result).to have_key(f)
      end
    end
  end

  # -----------------------------------------------------------------
  # deleteLocation -- deleteLocationFromServer
  # -----------------------------------------------------------------
  describe 'deleteLocation (SeedTrialReports/action.js deleteLocationFromServer)' do
    let(:location) { create(:location, owned_by: user.email, created_by: user.email) }

    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: DeleteLocationInput!) {
          deleteLocation(input: $input) {
            locationId
            clientMutationId
            errors {
              code
              field
              message
              value
            }
          }
        }
      GRAPHQL
    end

    it 'deletes and returns locationId with empty errors' do
      loc_id = PlantApiSchema.id_from_object(location, Location, {})
      result = PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: { input: { locationId: loc_id } }
      )
      expect(result['errors']).to be_nil
      payload = result.dig('data', 'deleteLocation')
      expect(payload['locationId']).to be_present
      expect(payload['errors']).to be_an(Array)
    end
  end

  # -----------------------------------------------------------------
  # softDeletePlant -- deletePlantFromServer (MyPlants/index.js)
  # The app checks: errors[0].code === 400 to detect dependency failures.
  # -----------------------------------------------------------------
  describe 'softDeletePlant (MyPlants/index.js deletePlantFromServer)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: SoftDeletePlantInput!) {
          softDeletePlant(input: $input) {
            plant {
              id
              primaryCommonName
            }
            clientMutationId
            errors {
              code
              field
              message
              value
            }
          }
        }
      GRAPHQL
    end

    context 'when the plant has no dependent records' do
      let(:plant) do
        create(:plant, :private, scientific_name: 'Lens culinaris',
                                 owned_by: user.email, created_by: user.email)
      end

      it 'soft-deletes the plant and returns an empty errors array' do
        plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
        result = PlantApiSchema.execute(
          mutation,
          context: { current_user: user },
          variables: { input: { plantId: plant_id } }
        )
        expect(result['errors']).to be_nil
        payload = result.dig('data', 'softDeletePlant')
        expect(payload['errors']).to be_an(Array)
        expect(payload['errors']).to be_empty
        plant.reload
        expect(plant.visibility_deleted?).to be true
      end
    end

    context 'when the plant has active varieties (dependency check)' do
      let(:plant) { create(:plant, :private, owned_by: user.email, created_by: user.email) }
      let!(:variety) { create(:variety, :private, plant: plant, owned_by: user.email, created_by: user.email) }

      it 'returns an errors array with code 400 and the plantId field' do
        plant_id = PlantApiSchema.id_from_object(plant, Plant, {})
        result = PlantApiSchema.execute(
          mutation,
          context: { current_user: user },
          variables: { input: { plantId: plant_id } }
        )
        expect(result['errors']).to be_nil
        payload = result.dig('data', 'softDeletePlant')
        errors = payload['errors']
        expect(errors).not_to be_empty
        first_error = errors.first
        # The app branches on: errors[0].code === 400
        expect(first_error['code']).to eq(400)
        # The app reads all four keys
        expect(first_error).to have_key('code')
        expect(first_error).to have_key('field')
        expect(first_error).to have_key('message')
        expect(first_error).to have_key('value')
      end
    end
  end

  # -----------------------------------------------------------------
  # softDeleteVariety -- deleteVarietyFromServer (MyVariety/index.js)
  # -----------------------------------------------------------------
  describe 'softDeleteVariety (MyVariety/index.js deleteVarietyFromServer)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: SoftDeleteVarietyInput!) {
          softDeleteVariety(input: $input) {
            variety {
              id
              name
            }
            clientMutationId
            errors {
              code
              field
              message
              value
            }
          }
        }
      GRAPHQL
    end

    context 'when the variety has no dependent specimens' do
      let(:variety) { create(:variety, :private, owned_by: user.email, created_by: user.email) }

      it 'soft-deletes and returns empty errors' do
        variety_id = PlantApiSchema.id_from_object(variety, Variety, {})
        result = PlantApiSchema.execute(
          mutation,
          context: { current_user: user },
          variables: { input: { varietyId: variety_id } }
        )
        expect(result['errors']).to be_nil
        payload = result.dig('data', 'softDeleteVariety')
        expect(payload['errors']).to be_empty
        variety.reload
        expect(variety.visibility_deleted?).to be true
      end
    end

    context 'when the variety has active specimens (dependency check)' do
      let(:variety) { create(:variety, :private, owned_by: user.email, created_by: user.email) }
      let!(:specimen) do
        create(:specimen, :private, variety: variety,
                                    owned_by: user.email, created_by: user.email)
      end

      it 'returns errors[0].code == 400 with all four keys' do
        variety_id = PlantApiSchema.id_from_object(variety, Variety, {})
        result = PlantApiSchema.execute(
          mutation,
          context: { current_user: user },
          variables: { input: { varietyId: variety_id } }
        )
        expect(result['errors']).to be_nil
        errors = result.dig('data', 'softDeleteVariety', 'errors')
        expect(errors).not_to be_empty
        first_error = errors.first
        expect(first_error['code']).to eq(400)
        %w[code field message value].each { |k| expect(first_error).to have_key(k) }
      end
    end
  end

  # -----------------------------------------------------------------
  # softDeleteLocation -- deleteLocationFromServer (MyLocations/index.js)
  # Note: the app uses softDeleteLocation, NOT the deleteLocation hard-delete.
  # -----------------------------------------------------------------
  describe 'softDeleteLocation (MyLocations/index.js deleteLocationFromServer)' do
    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: SoftDeleteLocationInput!) {
          softDeleteLocation(input: $input) {
            location {
              id
              name
            }
            clientMutationId
            errors {
              code
              field
              message
              value
            }
          }
        }
      GRAPHQL
    end

    context 'when the location has no dependent records' do
      let(:location) { create(:location, owned_by: user.email, created_by: user.email) }

      it 'soft-deletes and returns empty errors' do
        loc_id = PlantApiSchema.id_from_object(location, Location, {})
        result = PlantApiSchema.execute(
          mutation,
          context: { current_user: user },
          variables: { input: { locationId: loc_id } }
        )
        expect(result['errors']).to be_nil
        payload = result.dig('data', 'softDeleteLocation')
        expect(payload['errors']).to be_empty
        location.reload
        expect(location.visibility_deleted?).to be true
      end
    end

    context 'when the location is used by an active planting event (dependency check)' do
      let(:location) { create(:location, owned_by: user.email, created_by: user.email) }
      let(:specimen) { create(:specimen, owned_by: user.email, created_by: user.email) }
      let!(:planting_event) { create(:planting_event, specimen: specimen, location: location) }

      it 'returns errors[0].code == 400 with all four keys' do
        loc_id = PlantApiSchema.id_from_object(location, Location, {})
        result = PlantApiSchema.execute(
          mutation,
          context: { current_user: user },
          variables: { input: { locationId: loc_id } }
        )
        expect(result['errors']).to be_nil
        errors = result.dig('data', 'softDeleteLocation', 'errors')
        expect(errors).not_to be_empty
        first_error = errors.first
        expect(first_error['code']).to eq(400)
        %w[code field message value].each { |k| expect(first_error).to have_key(k) }
      end
    end
  end

  # -----------------------------------------------------------------
  # createImage -- createImageInServer
  # The app selects: errors{ field value message code }
  #   image{ id name description attribution baseUrl createdBy ownedBy
  #          imageAttributes{ id } }
  # -----------------------------------------------------------------
  describe 'createImage (SeedTrialReports/action.js createImageInServer)' do
    let(:plant) { create(:plant, :public, owned_by: user.email, created_by: user.email) }

    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: CreateImageInput!) {
          createImage(input: $input) {
            errors {
              field
              value
              message
              code
            }
            image {
              id
              name
              description
              attribution
              baseUrl
              createdBy
              ownedBy
              imageAttributes {
                id
              }
            }
          }
        }
      GRAPHQL
    end

    it 'creates and returns the full image shape the app reads' do
      imageable_id = PlantApiSchema.id_from_object(plant, Plant, {})
      result = PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: {
          input: {
            imageId: SecureRandom.uuid,
            objectId: imageable_id,
            bucket: 'images-us-east-1.echocommunity.org',
            key: 'test/mobile_image.jpg',
            name: 'Mobile Upload',
            description: 'From mobile app test',
            attribution: 'Photographer Name',
            language: 'en'
          }
        }
      )
      expect(result['errors']).to be_nil
      img = result.dig('data', 'createImage', 'image')
      expect(img['id']).to be_present
      expect(img['name']).to eq('Mobile Upload')
      expect(img['createdBy']).to eq(user.email)
      expect(img['ownedBy']).to eq(user.email)
      expect(img['imageAttributes']).to be_an(Array)
      errors = result.dig('data', 'createImage', 'errors')
      expect(errors).to be_an(Array)
      expect(errors).to be_empty
    end
  end

  # -----------------------------------------------------------------
  # deleteImage -- deleteImageFromServer
  # -----------------------------------------------------------------
  describe 'deleteImage (SeedTrialReports/action.js deleteImageFromServer)' do
    let(:plant) { create(:plant, :public, owned_by: user.email, created_by: user.email) }
    let(:image) do
      create(:image, :private, imageable: plant,
                               owned_by: user.email, created_by: user.email)
    end

    let(:mutation) do
      <<~GRAPHQL
        mutation ($input: DeleteImageInput!) {
          deleteImage(input: $input) {
            imageId
            clientMutationId
            errors {
              message
            }
          }
        }
      GRAPHQL
    end

    it 'deletes and returns imageId with empty errors' do
      image_id = PlantApiSchema.id_from_object(image, Image, {})
      result = PlantApiSchema.execute(
        mutation,
        context: { current_user: user },
        variables: { input: { imageId: image_id } }
      )
      expect(result['errors']).to be_nil
      payload = result.dig('data', 'deleteImage')
      expect(payload['imageId']).to be_present
      expect(payload['errors']).to be_an(Array)
    end
  end
end
