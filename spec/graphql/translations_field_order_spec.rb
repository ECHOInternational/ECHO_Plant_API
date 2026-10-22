# frozen_string_literal: true

require 'rails_helper'

# The "translations field-order trap": Mobility's container backend creates a
# locale entry the moment ANY translated attribute is written in that locale.
# Writing only `description` in a new locale (before the name, or never) leaves
# an entry with no `name`, and the lookup types declare `name` non-null, so one
# such row made the whole `translations` field error for every client that
# selected it. translations_array now skips locales that have no name.
RSpec.describe 'translations_array skips nameless locales' do
  {
    category: { root: 'categories', description: true },
    tolerance: { root: 'tolerances', description: false },
    antinutrient: { root: 'antinutrients', description: false },
    growth_habit: { root: 'growthHabits', description: false },
    image_attribute: { root: 'imageAttributes', description: false }
  }.each do |factory, config|
    describe factory.to_s.camelize do
      let(:record) { create(factory) }
      let(:nameless) do
        # Mimics the trap: a locale entry that exists but carries no name.
        { 'fr' => (config[:description] ? { 'description' => 'Seulement une description' } : {}) }
      end

      # Mobility drops empty single-attribute entries when it reads the column
      # back, so only Category can hold a nameless locale in the database. The
      # stub feeds every model the raw hash the guard has to cope with.
      def stub_raw_translations(record, raw)
        allow(record).to receive(:translations).and_return(raw)
      end

      it 'returns only locales that have a name' do
        stub_raw_translations(record, 'en' => { 'name' => 'Name' }, **nameless, 'de' => { 'name' => nil },
                                      'it' => { 'name' => '' })
        locales = record.translations_array.map { |entry| entry[:locale] }
        expect(locales).to eq(['en'])
      end

      it 'still returns each named locale with its name' do
        stub_raw_translations(record, 'en' => { 'name' => 'Name' }, 'es' => { 'name' => 'Nombre' }, **nameless)
        entries = record.translations_array
        expect(entries.map { |e| [e[:locale], e[:name]] }).to eq([%w[en Name], %w[es Nombre]])
      end

      it 'lets the GraphQL translations field resolve without a non-null error' do
        record.update_columns(translations: record.translations.merge(nameless))
        query = "{ #{config[:root]}(first: 50) { nodes { translations { locale name } } } }"
        result = PlantApiSchema.execute(query, context: { current_user: nil })
        expect(result['errors']).to be_nil
        nodes = result.dig('data', config[:root], 'nodes')
        expect(nodes.flat_map { |n| n['translations'].map { |t| t['name'] } }).not_to include(nil)
      end
    end
  end
end
