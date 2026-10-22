# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ImagePositions do
  let(:plant) { create(:plant) }
  let(:other_plant) { create(:plant) }
  let(:drawing) { create(:image_attribute, name: 'Drawing') }

  # Images as the backfill finds them: no position yet.
  def image(parent = plant, source: nil, drawing_tag: false, created_at: Time.zone.parse('2020-01-01'))
    img = create(:image, imageable: parent, source_record_id: source, created_at: created_at)
    img.image_attribute_ids = [drawing.id] if drawing_tag
    img.update_columns(position: nil)
    img
  end

  def ordered(parent = plant)
    Image.where(imageable: parent).order(:position).pluck(:id)
  end

  it 'puts FPI photos first in numeric rowid order, then drawings in rowid order' do
    d2 = image(source: 'drawings:2', drawing_tag: true)
    p10 = image(source: 'photos:10')
    d1 = image(source: 'drawings:1', drawing_tag: true)
    p9 = image(source: 'photos:9')

    described_class.backfill!

    expect(ordered).to eq [p9.id, p10.id, d1.id, d2.id]
    expect(Image.where(imageable: plant).order(:position).pluck(:position)).to eq [1, 2, 3, 4]
  end

  it 'puts photos before Drawing-tagged images, then oldest first, then id' do
    newer = image(created_at: Time.zone.parse('2021-01-01'))
    tagged = image(drawing_tag: true, created_at: Time.zone.parse('2019-01-01'))
    older = image(created_at: Time.zone.parse('2020-01-01'))

    described_class.backfill!

    expect(ordered).to eq [older.id, newer.id, tagged.id]
  end

  it 'recognises the Drawing tag by its English name whatever the request locale' do
    tagged = image(drawing_tag: true, created_at: Time.zone.parse('2019-01-01'))
    photo = image(created_at: Time.zone.parse('2020-01-01'))

    Mobility.with_locale(:fr) { described_class.backfill! }

    expect(ordered).to eq [photo.id, tagged.id]
  end

  it 'numbers each parent separately and walks parents in batches' do
    a = Array.new(3) { |i| image(created_at: Time.zone.parse("2020-01-0#{i + 1}")) }
    b = Array.new(2) { |i| image(other_plant, created_at: Time.zone.parse("2020-01-0#{i + 1}")) }

    described_class.backfill!(batch_size: 1)

    expect(ordered).to eq a.map(&:id)
    expect(ordered(other_plant)).to eq b.map(&:id)
    expect(Image.where(imageable: other_plant).order(:position).pluck(:position)).to eq [1, 2]
  end

  it 'preserves updated_at and writes no versions', versioning: true do
    img = image
    stamp = img.reload.updated_at

    expect { described_class.backfill! }.not_to change(PaperTrail::Version, :count)
    expect(img.reload.updated_at).to eq stamp
    expect(img.position).to eq 1
  end

  it 'is resumable: rows already positioned keep their place and new ones go after them' do
    first = image(created_at: Time.zone.parse('2019-01-01'))
    first.update_columns(position: 5)
    late = image(created_at: Time.zone.parse('2018-01-01'))

    described_class.backfill!
    described_class.backfill!

    expect(first.reload.position).to eq 5
    expect(late.reload.position).to eq 6
  end
end
