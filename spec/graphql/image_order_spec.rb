# frozen_string_literal: true

require 'rails_helper'

# FPI plan API-5: every images connection is in display order (images.position)
# and ImageType exposes position and isDrawing. The Drawing tag is recognised
# by its English name whatever the request language.
RSpec.describe 'Image display order', type: :graphql_query do
  let(:drawing) do
    attr = create(:image_attribute, name: 'Drawing')
    Mobility.with_locale(:fr) { attr.update!(name: 'Dessin') }
    Mobility.with_locale(:es) { attr.update!(name: 'Dibujo') }
    attr
  end

  before { Mobility.locale = nil }

  def gid(record, type = record.class)
    PlantApiSchema.id_from_object(record, type, {})
  end

  # Three public images created in one order and positioned in another.
  def positioned_images(parent)
    images = Array.new(3) { create(:image, :public, imageable: parent) }
    images.zip([3, 1, 2]).each { |img, pos| img.update_columns(position: pos) }
    images.sort_by(&:position).map(&:id)
  end

  def run(query, **vars)
    result = PlantApiSchema.execute(query, variables: vars, context: { current_user: nil })
    expect(result['errors']).to be_nil
    result['data']
  end

  def uuids(connection)
    connection['nodes'].pluck('uuid')
  end

  %w[fr es en].each do |language|
    it "orders plant images by position and flags drawings with language #{language}" do
      plant = create(:plant, :public)
      tagged = create(:image, :public, imageable: plant, image_attribute_ids: [drawing.id])
      photo = create(:image, :public, imageable: plant)
      tagged.update_columns(position: 2)
      photo.update_columns(position: 1)

      data = run(<<~GRAPHQL, id: gid(plant), language: language)
        query($id: ID!, $language: String) {
          plant(id: $id, language: $language) { images { nodes { uuid position isDrawing } } }
        }
      GRAPHQL

      expect(data.dig('plant', 'images', 'nodes')).to eq [
        { 'uuid' => photo.id, 'position' => 1, 'isDrawing' => false },
        { 'uuid' => tagged.id, 'position' => 2, 'isDrawing' => true }
      ]
    end
  end

  it 'makes images(first: 1) deterministic: the lowest position wins' do
    plant = create(:plant, :public)
    expected = positioned_images(plant)
    data = run('query($id: ID!) { plant(id: $id) { images(first: 1) { nodes { uuid } } } }', id: gid(plant))
    expect(uuids(data.dig('plant', 'images'))).to eq [expected.first]
  end

  it 'orders variety images' do
    variety = create(:variety, :public)
    expected = positioned_images(variety)
    data = run('query($id: ID!) { variety(id: $id) { images { nodes { uuid } } } }', id: gid(variety))
    expect(uuids(data.dig('variety', 'images'))).to eq expected
  end

  it 'orders category images' do
    category = create(:category, :public)
    expected = positioned_images(category)
    data = run('query($id: ID!) { category(id: $id) { images { nodes { uuid } } } }', id: gid(category))
    expect(uuids(data.dig('category', 'images'))).to eq expected
  end

  it 'orders specimen images' do
    specimen = create(:specimen, :public)
    expected = positioned_images(specimen)
    data = run('query($id: ID!) { specimen(id: $id) { images { nodes { uuid } } } }', id: gid(specimen))
    expect(uuids(data.dig('specimen', 'images'))).to eq expected
  end

  it 'orders location images' do
    location = create(:location, :public)
    expected = positioned_images(location)
    data = run('query($id: ID!) { location(id: $id) { images { nodes { uuid } } } }', id: gid(location))
    expect(uuids(data.dig('location', 'images'))).to eq expected
  end

  it 'orders life-cycle event images' do
    event = create(:harvest_event, specimen: create(:specimen, :public))
    expected = positioned_images(event)
    data = run('query($id: ID!) { lifeCycleEvent(id: $id) { images { nodes { uuid } } } }',
               id: gid(event, HarvestEvent))
    expect(uuids(data.dig('lifeCycleEvent', 'images'))).to eq expected
  end

  it 'resolves isDrawing for many images with one tag query per request' do
    plants = Array.new(3) { create(:plant, :public) }
    plants.each do |plant|
      create(:image, :public, imageable: plant, image_attribute_ids: [drawing.id])
      create(:image, :public, imageable: plant)
    end

    tag_queries = 0
    counter = lambda do |*, payload|
      tag_queries += 1 if payload[:sql].include?('image_attributes_images')
    end
    data = ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
      run('{ plants(first: 10) { nodes { images { nodes { isDrawing } } } } }')
    end

    flags = data.dig('plants', 'nodes').flat_map { |n| n.dig('images', 'nodes').pluck('isDrawing') }
    expect(flags.tally).to eq(true => 3, false => 3)
    expect(tag_queries).to eq 1
  end
end
