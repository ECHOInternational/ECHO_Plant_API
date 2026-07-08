# frozen_string_literal: true

# Shared examples for the simple lookup CRUD mutations (Tolerance, GrowthHabit,
# Antinutrient, ImageAttribute): super-admin-only writes on models with a single
# translatable :name.
RSpec.shared_examples 'a lookup create mutation' do |model:|
  field_name = "create#{model.name}"
  record_field = model.name.camelize(:lower)
  query_string = <<-GRAPHQL
    mutation($input: Create#{model.name}Input!){
      #{field_name}(input: $input){
        errors { field message code }
        #{record_field} { id uuid name }
      }
    }
  GRAPHQL

  context 'when user is not authenticated' do
    it 'returns a 401 error' do
      result = PlantApiSchema.execute(query_string, context: { current_user: nil },
                                                    variables: { input: { name: 'Frost' } })
      expect(result['errors'][0]['extensions']['code']).to eq 401
    end
  end

  context 'when user is read/write but not super admin' do
    it 'returns a 403 error' do
      result = PlantApiSchema.execute(query_string, context: { current_user: build(:user, :readwrite) },
                                                    variables: { input: { name: 'Frost' } })
      expect(result['errors'][0]['extensions']['code']).to eq 403
    end
  end

  context 'when user is a super admin' do
    let(:current_user) { build(:user, :superadmin) }

    it 'creates a record' do
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user },
                                                    variables: { input: { name: 'Frost' } })
      record_result = result['data'][field_name][record_field]
      expect(record_result['name']).to eq 'Frost'
      expect(model.find(record_result['uuid']).name).to eq 'Frost'
    end

    it 'stores translations in the requested language' do
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user },
                                                    variables: { input: { name: 'Helada', language: 'es' } })
      created = model.find(result['data'][field_name][record_field]['uuid'])
      expect(created.translations).to include 'es'
      expect(created.translations).to_not include 'en'
    end

    it 'returns payload errors for invalid input' do
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user },
                                                    variables: { input: { name: '' } })
      error_result = result['data'][field_name]['errors']
      expect(error_result[0]['field']).to eq 'name'
      expect(error_result[0]['code']).to eq 400
    end
  end
end

RSpec.shared_examples 'a lookup update mutation' do |model:, factory:|
  field_name = "update#{model.name}"
  record_field = model.name.camelize(:lower)
  id_field = "#{record_field}Id"
  query_string = <<-GRAPHQL
    mutation($input: Update#{model.name}Input!){
      #{field_name}(input: $input){
        errors { field message code }
        #{record_field} { id uuid name }
      }
    }
  GRAPHQL

  let!(:record) { create(factory) }
  let(:record_gid) { PlantApiSchema.id_from_object(record, model, {}) }

  it 'returns a 403 error for non-super-admin users' do
    result = PlantApiSchema.execute(query_string, context: { current_user: build(:user, :readwrite) },
                                                  variables: { input: { id_field => record_gid, name: 'Updated' } })
    expect(result['errors'][0]['extensions']['code']).to eq 403
  end

  context 'when user is a super admin' do
    let(:current_user) { build(:user, :superadmin) }

    it 'updates the name' do
      result = PlantApiSchema.execute(query_string, context: { current_user: current_user },
                                                    variables: { input: { id_field => record_gid, name: 'Updated' } })
      expect(result['data'][field_name][record_field]['name']).to eq 'Updated'
      expect(record.reload.name).to eq 'Updated'
    end

    it 'writes the requested language' do
      PlantApiSchema.execute(query_string, context: { current_user: current_user },
                                           variables: { input: { id_field => record_gid, name: 'Actualizado', language: 'es' } })
      expect(record.reload.translations).to include 'es'
    end
  end
end

RSpec.shared_examples 'a lookup delete mutation' do |model:, factory:|
  field_name = "delete#{model.name}"
  id_field = "#{model.name.camelize(:lower)}Id"
  query_string = <<-GRAPHQL
    mutation($input: Delete#{model.name}Input!){
      #{field_name}(input: $input){
        errors { field message code }
        #{id_field}
      }
    }
  GRAPHQL

  let!(:record) { create(factory) }
  let(:record_gid) { PlantApiSchema.id_from_object(record, model, {}) }

  it 'returns a 403 error for non-super-admin users' do
    result = PlantApiSchema.execute(query_string, context: { current_user: build(:user, :readwrite) },
                                                  variables: { input: { id_field => record_gid } })
    expect(result['errors'][0]['extensions']['code']).to eq 403
    expect(model.exists?(record.id)).to be true
  end

  it 'destroys the record for super admins' do
    result = PlantApiSchema.execute(query_string, context: { current_user: build(:user, :superadmin) },
                                                  variables: { input: { id_field => record_gid } })
    expect(result['data'][field_name][id_field]).to eq record_gid
    expect(model.exists?(record.id)).to be false
  end
end
