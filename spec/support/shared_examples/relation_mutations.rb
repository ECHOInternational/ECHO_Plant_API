# frozen_string_literal: true

# Shared examples for set-style relation mutations (updatePlantCategories etc.).
# The supplied id list REPLACES the association; empty list clears it.
RSpec.shared_examples 'a relation set mutation' do |field_name:, owner_factory:, owner_key:, items_factory:, ids_key:, association:| # rubocop:disable Metrics/ParameterLists
  input_type = "#{field_name[0].upcase}#{field_name[1..]}Input"
  query_string = <<-GRAPHQL
    mutation($input: #{input_type}!){
      #{field_name}(input: $input){
        errors { field message code }
        #{owner_key} { uuid }
      }
    }
  GRAPHQL

  let(:current_user) { build(:user, :readwrite) }
  let!(:owner) { create(owner_factory, owned_by: current_user.email, created_by: current_user.email) }
  let(:owner_gid) { PlantApiSchema.id_from_object(owner, owner.class, {}) }
  let!(:item_a) { create(items_factory) }
  let!(:item_b) { create(items_factory) }

  def item_gid(item)
    PlantApiSchema.id_from_object(item, item.class, {})
  end

  it 'replaces the association with the supplied set' do
    owner.public_send(association) << item_a
    PlantApiSchema.execute(query_string, context: { current_user: current_user },
                                         variables: { input: { "#{owner_key}Id" => owner_gid, ids_key => [item_gid(item_b)] } })
    expect(owner.reload.public_send(association)).to contain_exactly(item_b)
  end

  it 'clears the association with an empty list' do
    owner.public_send(association) << item_a
    PlantApiSchema.execute(query_string, context: { current_user: current_user },
                                         variables: { input: { "#{owner_key}Id" => owner_gid, ids_key => [] } })
    expect(owner.reload.public_send(association)).to be_empty
  end

  it 'rejects non-owners with 403' do
    result = PlantApiSchema.execute(query_string, context: { current_user: build(:user, :readwrite) },
                                                  variables: { input: { "#{owner_key}Id" => owner_gid, ids_key => [] } })
    expect(result['errors'][0]['extensions']['code']).to eq 403
  end
end
