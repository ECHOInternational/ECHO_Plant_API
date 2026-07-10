# frozen_string_literal: true

require 'rails_helper'

# Compatibility guard for the mobility 0.8.13 -> 1.2.9 bump on frozen Rails 6.1 / Ruby 2.7.
#
# Mobility 0.8 -> 1.x rewrote configuration (a global Mobility.configure block became a
# per-model plugins DSL). The danger of that bump is NOT a crash - it is SILENT SEMANTIC
# DRIFT: fallbacks, presence (blank-vs-nil), dirty tracking, and locale-scoped queries can
# change behaviour while every request still returns 200, just with wrong-language content.
# This API serves translated plant data to external consumers in multiple locales.
#
# Every example below pins a behaviour AS OBSERVED ON 0.8.13 and each carries a one-line
# comment naming the drift it guards. This spec is committed and proven green on 0.8 BEFORE
# the gem bump, and must pass UNCHANGED afterwards. It is a tripwire: do not relax an
# assertion to make 1.x pass - a red example here means a real semantic moved.
RSpec.describe 'Mobility 1.x compatibility', type: :model do
  before { Mobility.locale = nil }
  after { Mobility.locale = nil }

  # (a) DATA FORMAT: the raw jsonb container layout must stay {"locale" => {"attr" => v}}.
  # The migration claim is "jsonb layout unchanged"; this proves it at the storage level.
  describe 'raw storage layout (container backend)' do
    it 'stores translations as a per-locale nested jsonb hash keyed by attribute' do
      plant = create(:plant)
      Mobility.with_locale(:en) { plant.origin = 'English origin' }
      Mobility.with_locale(:es) { plant.origin = 'Origen espanol' }
      plant.save!
      plant.reload

      raw = plant.read_attribute(:translations)

      expect(raw).to be_a(Hash)
      expect(raw['en']).to include('origin' => 'English origin')
      expect(raw['es']).to eq('origin' => 'Origen espanol')
      # attributes hash exposes the same raw container (not a decoded/locale-scoped view).
      expect(plant.attributes['translations']).to eq(raw)
    end
  end

  # (b) LOCALE READS: reading under an explicit locale returns that locale's value.
  describe 'locale reads' do
    it 'returns the value for the active locale' do
      plant = create(:plant)
      Mobility.with_locale(:en) { plant.origin = 'English origin' }
      Mobility.with_locale(:es) { plant.origin = 'Origen espanol' }
      plant.save!
      plant.reload

      expect(Mobility.with_locale(:en) { plant.origin }).to eq('English origin')
      expect(Mobility.with_locale(:es) { plant.origin }).to eq('Origen espanol')
    end
  end

  # (c) FALLBACKS: reading a missing locale falls back to the default locale (:en) value;
  # a value present in NO locale reads as nil. Fallback config is a known 0.8->1.x drift point.
  describe 'fallbacks' do
    it 'falls back to the :en value when the requested locale is missing' do
      plant = create(:plant)
      Mobility.with_locale(:en) { plant.origin = 'English origin' }
      plant.save!
      plant.reload

      # :es and :fr have no origin translation -> fall back to :en.
      expect(Mobility.with_locale(:es) { plant.origin }).to eq('English origin')
      expect(Mobility.with_locale(:fr) { plant.origin }).to eq('English origin')
    end

    it 'returns nil for an attribute translated in no locale at all' do
      plant = create(:plant)
      plant.save!
      plant.reload

      # :uses is never set in any locale -> nil, not "" and not a fallback ghost.
      expect(Mobility.with_locale(:en) { plant.uses }).to be_nil
      expect(Mobility.with_locale(:fr) { plant.uses }).to be_nil
    end
  end

  # (d) PRESENCE: the presence plugin converts "" to nil on both read and write, and an
  # empty string is NOT persisted into the raw container. This is a known 0.8->1.x drift point.
  describe 'presence (blank-to-nil)' do
    it 'reads "" back as nil and does not persist the empty string' do
      plant = create(:plant)
      Mobility.with_locale(:en) { plant.origin = 'English origin' }
      plant.save!
      plant.reload

      Mobility.with_locale(:en) { plant.cultivation = '' }
      # read of a just-set "" is nil (presence on the reader)
      expect(Mobility.with_locale(:en) { plant.cultivation }).to be_nil

      plant.save!
      plant.reload
      expect(Mobility.with_locale(:en) { plant.cultivation }).to be_nil
      # "" never entered the raw container: the en hash has origin but no cultivation key.
      expect(plant.read_attribute(:translations)['en']).not_to have_key('cultivation')
    end
  end

  # (e) DIRTY: changing a translated attr marks the record dirty, exposes an
  # [old, new] change tuple via the bare-attr accessor, tracks the locale-suffixed shadow
  # attribute in changed_attributes, and clears on save. PaperTrail versioning of a
  # translated change rides on this dirty machinery, so a version row must record it.
  describe 'dirty tracking' do
    it 'tracks a translated-attr change and clears it on save' do
      Mobility.locale = :en
      plant = create(:plant)
      plant.reload
      Mobility.locale = :en

      plant.pests_and_diseases = 'new pest text'

      expect(plant.changed?).to be(true)
      # bare-attr dirty accessors work via fallthrough; tuple is [old, new].
      expect(plant.pests_and_diseases_changed?).to be(true)
      expect(plant.pests_and_diseases_change).to eq([nil, 'new pest text'])
      # the change is carried on the locale-suffixed shadow attribute in changed_attributes.
      expect(plant.changed_attributes.keys).to include('pests_and_diseases_en')

      plant.save!
      expect(plant.changed?).to be(false)
    end

    it 'records the translations change in a PaperTrail version on update', versioning: true do
      Mobility.locale = :en
      plant = create(:plant)
      plant.reload
      Mobility.locale = :en

      PaperTrail.request.whodunnit = 'editor@example.org'

      expect do
        plant.update!(origin: 'Changed Origin EN')
      end.to change { PaperTrail::Version.where(item_type: 'Plant').count }.by(1)

      version = PaperTrail::Version.where(item_type: 'Plant').order(:created_at).last
      expect(version.event).to eq('update')
      object = PaperTrail.serializer.load(version.object)
      # the versioned object payload carries the translations container (pre-update state).
      expect(object).to have_key('translations')
    end
  end

  # (f) QUERY / .i18n: a locale-scoped query matches a record under its own locale value and
  # does NOT match the same record when a different locale is active. This is the scope every
  # collection resolver relies on; a drift here silently cross-contaminates search by language.
  describe 'query via the .i18n scope' do
    it 'matches under the correct locale and not under a different locale' do
      category = create(:category)
      Mobility.with_locale(:en) { category.update!(name: 'Legumes') }
      Mobility.with_locale(:es) { category.update!(name: 'Legumbres') }

      en_hits = Mobility.with_locale(:en) { Category.i18n { name.eq('Legumes') }.to_a }
      es_cross = Mobility.with_locale(:es) { Category.i18n { name.eq('Legumes') }.to_a }
      es_hits = Mobility.with_locale(:es) { Category.i18n { name.eq('Legumbres') }.to_a }

      expect(en_hits.map(&:id)).to include(category.id)
      expect(es_cross.map(&:id)).not_to include(category.id) # no cross-locale leak
      expect(es_hits.map(&:id)).to include(category.id)
    end
  end

  # (g) GRAPHQL END-TO-END: what external consumers actually see. The single-plant query's
  # `language` argument sets Mobility.locale; per-locale values come back correctly and a
  # missing locale falls back to :en. This is the request-level guard against wrong-language 200s.
  describe 'GraphQL request-level locale switching' do
    it 'returns per-locale values and falls back for a missing locale' do
      plant = create(:plant, :public)
      Mobility.with_locale(:en) { plant.update!(origin: 'English Origin') }
      Mobility.with_locale(:es) { plant.update!(origin: 'Origen Espanol') }
      plant_id = PlantApiSchema.id_from_object(plant, Plant, {})

      query = <<-GRAPHQL
        query($id: ID!, $lang: String){
          plant(id: $id, language: $lang){ id origin }
        }
      GRAPHQL

      en = PlantApiSchema.execute(query, variables: { id: plant_id, lang: 'en' })
      es = PlantApiSchema.execute(query, variables: { id: plant_id, lang: 'es' })
      fr = PlantApiSchema.execute(query, variables: { id: plant_id, lang: 'fr' })

      expect(en['data']['plant']['origin']).to eq('English Origin')
      expect(es['data']['plant']['origin']).to eq('Origen Espanol')
      # fr has no translation -> falls back to :en value, not nil, not es.
      expect(fr['data']['plant']['origin']).to eq('English Origin')
    end
  end
end
