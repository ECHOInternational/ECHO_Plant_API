# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CommonNameCorrections do
  # Every correction is addressed to a real plant, so the specs build the plants
  # the constants name rather than inventing their own.
  let(:acacia) { create(:plant, scientific_name: 'Acacia tumida') }
  let(:capsicum) { create(:plant, scientific_name: 'Capsicum annuum') }
  let(:okra) { create(:plant, scientific_name: 'Abelmoschus caillei') }

  def run(apply: false)
    described_class.new(apply: apply).run
  end

  describe 'deletions' do
    it 'removes a flagged name when applying' do
      name = create(:common_name, plant: acacia, name: 'Acacia', language: 'en')

      result = run(apply: true)

      expect(result.deleted).to be >= 1
      expect(CommonName.exists?(name.id)).to be false
    end

    it 'changes nothing on a dry run, while still reporting what it would do' do
      name = create(:common_name, plant: acacia, name: 'Acacia', language: 'en')

      result = run

      expect(result.deleted).to be >= 1
      expect(result.lines).to include(a_string_matching(/DELETE\s+Acacia tumida: Acacia \(en\)/))
      expect(CommonName.exists?(name.id)).to be true
    end

    # The factory stores 'EN'; the corrections say 'en'. A case-sensitive match
    # would silently find nothing and report every row as already gone.
    it 'matches the language case-insensitively' do
      name = create(:common_name, plant: acacia, name: 'ACACIA', language: 'EN')

      run(apply: true)

      expect(CommonName.exists?(name.id)).to be false
    end

    it 'reports a name that is already gone instead of failing' do
      acacia
      result = run(apply: true)

      expect(result.already_gone).to be >= 1
      expect(result.errors).to be_empty
    end
  end

  describe 'retags' do
    it 'moves the name to Spanish, fixes the spacing, and clears the primary flag' do
      name = create(:common_name, plant: okra, name: 'Quimbombótardio', language: 'en',
                                  primary: true)

      result = run(apply: true)

      expect(result.retagged).to be >= 1
      name.reload
      expect(name.name).to eq('Quimbombó tardío')
      expect(name.language).to eq('es')
      # `primary` is per language: an English primary must not become the name
      # every Spanish reader sees.
      expect(name.primary).to be false
    end

    it 'deletes the mistagged row instead of creating a duplicate when the target exists' do
      mistagged = create(:common_name, plant: okra, name: 'Quimbombó', language: 'en')
      existing = create(:common_name, plant: okra, name: 'Quimbombó', language: 'es')

      result = run(apply: true)

      expect(result.would_collide).to eq(1)
      expect(CommonName.exists?(mistagged.id)).to be false
      expect(CommonName.exists?(existing.id)).to be true
    end
  end

  describe 'plants it cannot reach' do
    it 'counts a missing plant and carries on with the rest' do
      create(:common_name, plant: capsicum, name: 'Jalapeno', language: 'en')

      result = run(apply: true)

      # Only Capsicum annuum exists, so the three Acacias and the okra are absent.
      expect(result.missing_plants).to be >= 1
      expect(result.deleted).to eq(1)
      expect(result.errors).to be_empty
    end
  end

  describe 'the corrections themselves' do
    it 'names six rows, and every one carries a reason' do
      corrections = described_class::DELETIONS + described_class::RETAGS

      expect(corrections.length).to eq(6)
      expect(corrections).to all(include(:scientific_name, :name, :language, :why))
      expect(corrections.map { |c| c[:why] }).to all(be_present)
    end

    it 'sends every retag to a different language from the one it came from' do
      described_class::RETAGS.each do |retag|
        expect(retag[:to_language]).not_to eq(retag[:language])
      end
    end
  end
end
