# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Reorder Images Mutation', type: :graphql_mutation do
  let(:current_user) { build(:user, :readwrite) }
  let(:plant) { create(:plant, owned_by: current_user.email) }
  let!(:images) { Array.new(3) { create(:image, imageable: plant) } }
  let(:query_string) do
    <<~GRAPHQL
      mutation($input: ReorderImagesInput!) {
        reorderImages(input: $input) {
          images { uuid position }
          errors { field value message code }
        }
      }
    GRAPHQL
  end

  def gid(record, type = record.class)
    PlantApiSchema.id_from_object(record, type, {})
  end

  def reorder(ids, object: plant, user: current_user)
    PlantApiSchema.execute(query_string, context: { current_user: user },
                                         variables: { input: { objectId: gid(object), imageIds: ids } })
  end

  def positions
    Image.where(imageable: plant).order(:position).pluck(:id)
  end

  it 'renumbers the listed images 1..n in the given order and returns them in display order' do
    a, b, c = images
    result = reorder([gid(c), gid(a), gid(b)])

    payload = result.dig('data', 'reorderImages')
    expect(payload['errors']).to eq []
    expect(payload['images']).to eq [
      { 'uuid' => c.id, 'position' => 1 }, { 'uuid' => a.id, 'position' => 2 }, { 'uuid' => b.id, 'position' => 3 }
    ]
    expect(positions).to eq [c.id, a.id, b.id]
  end

  it 'puts unlisted images after the listed ones, keeping their relative order' do
    a, b, c = images
    reorder([gid(c)])
    expect(positions).to eq [c.id, a.id, b.id]
    expect(Image.where(imageable: plant).order(:position).pluck(:position)).to eq [1, 2, 3]
  end

  it 'touches the parent so delta readers see the change' do
    expect { reorder([gid(images.last)]) }.to(change { plant.reload.updated_at })
  end

  it 'refuses an image that belongs to another record and changes nothing' do
    stranger = create(:image, imageable: create(:plant, owned_by: current_user.email))
    before = positions
    payload = reorder([gid(stranger), gid(images.first)]).dig('data', 'reorderImages')

    expect(payload['images']).to be_nil
    expect(payload['errors']).to contain_exactly(include('field' => 'imageIds', 'code' => 404, 'value' => gid(stranger)))
    expect(positions).to eq before
  end

  it 'refuses a repeated image id' do
    payload = reorder([gid(images.first), gid(images.first)]).dig('data', 'reorderImages')
    expect(payload['errors']).to contain_exactly(include('field' => 'imageIds', 'code' => 400))
  end

  it 'is forbidden to a user who may not update the parent' do
    other = build(:user, :readwrite)
    result = reorder([gid(images.first)], user: other)
    expect(result['data']).to be_nil
    expect(result['errors'][0]['extensions']['code']).to eq 403
  end

  it 'is unauthenticated without a user' do
    result = reorder([gid(images.first)], user: nil)
    expect(result['errors'][0]['extensions']['code']).to eq 401
  end
end
