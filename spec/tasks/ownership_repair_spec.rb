# frozen_string_literal: true

require 'rails_helper'
require 'rake'
require 'tempfile'
require Rails.root.join('lib/ownership_repair')

# This task deletes production records. The two things that must be true before
# anyone runs it: the dry run writes nothing, and the deletion order respects
# the restrict_with_error associations rather than blowing past them.
RSpec.describe 'ownership:repair_unreachable', type: :task do
  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  before { Rake::Task['ownership:repair_unreachable'].reenable }

  # Config is written to a tempfile, never committed: the real one carries
  # personal data and this repository is public.
  def run(dry_run: true, link: [link_entry], purge: [purge_email])
    file = Tempfile.new(['repair', '.json'])
    file.write(JSON.generate('link' => link, 'purge' => purge))
    file.flush
    ENV['DRY_RUN'] = dry_run ? '1' : '0'
    ENV['REPAIR_MAPPING'] = file.path
    Rake::Task['ownership:repair_unreachable'].invoke
  ensure
    ENV.delete('DRY_RUN')
    ENV.delete('REPAIR_MAPPING')
    file&.close
    file&.unlink
  end

  # The shape the backfill left behind: a principal with no external_uid, so no
  # JWT can ever resolve to it, owning records through its personal org.
  def unreachable_owner(email)
    principal = Principal.create!(identity_issuer: OwnershipRepair::LEGACY_ISSUER,
                                  email: email, external_uid: nil, kind: 'human')
    Organization.personal_for!(principal)
  end

  # Fictional values. The real ones live in a private config supplied at runtime.
  let(:purge_email) { 'purge-me@example.test' }
  let(:link_email)  { 'old-address@example.test' }
  # Mixed case on purpose: uid comparison is case-sensitive.
  let(:link_uid)    { 'AB12CD34-5678-49AB-8CDE-F01234567890' }
  let(:link_target) { { uid: link_uid, email: 'new-address@example.test' } }
  let(:link_entry)  { { 'old_email' => link_email, 'uid' => link_uid, 'email' => link_target[:email] } }

  describe 'the dry run' do
    it 'writes nothing at all' do
      org = unreachable_owner(purge_email)
      create(:plant, owner_organization_id: org.id, source_organization_id: org.id)
      link_org = unreachable_owner(link_email)
      principal_before = Principal.find(link_org.principal_id).attributes

      expect { run(dry_run: true) }.to output(/DRY RUN complete/).to_stdout
      expect(Plant.where(owner_organization_id: org.id).count).to eq 1
      expect(Principal.find(link_org.principal_id).attributes).to eq principal_before
    end
  end

  describe 'linking' do
    it 'adopts the real uid onto the existing principal, so no record has to move' do
      org = unreachable_owner(link_email)
      plant = create(:plant, owner_organization_id: org.id, source_organization_id: org.id)

      run(dry_run: false)

      principal = Principal.find(org.principal_id)
      expect(principal.external_uid).to eq link_target[:uid]
      expect(principal.identity_issuer).to eq OwnershipRepair::ECHOCOMMUNITY_ISSUER
      expect(principal.email).to eq link_target[:email]
      # The record never moved -- its organization simply became reachable.
      expect(plant.reload.owner_organization_id).to eq org.id
    end

    it 'preserves uid case exactly, since resolution is a case-sensitive match' do
      expect(link_uid).not_to eq link_uid.downcase

      org = unreachable_owner(link_email)
      run(dry_run: false)
      expect(Principal.find(org.principal_id).external_uid).to eq link_target[:uid]
    end

    it 'repoints records instead when the person already signed in under the real address' do
      legacy_org = unreachable_owner(link_email)
      plant = create(:plant, owner_organization_id: legacy_org.id, source_organization_id: legacy_org.id)
      real = Principal.create!(identity_issuer: OwnershipRepair::ECHOCOMMUNITY_ISSUER,
                               external_uid: link_target[:uid], email: link_target[:email], kind: 'human')
      real_org = Organization.personal_for!(real)

      run(dry_run: false)

      expect(plant.reload.owner_organization_id).to eq real_org.id
    end
  end

  describe 'purging' do
    it 'deletes the records owned by a confirmed-disposable address' do
      org = unreachable_owner(purge_email)
      create(:location, owner_organization_id: org.id, source_organization_id: org.id)

      expect { run(dry_run: false) }.to change(Location, :count).by(-1)
    end

    it 'destroys a specimen before its location, so the location is not restricted' do
      org = unreachable_owner(purge_email)
      location = create(:location, owner_organization_id: org.id, source_organization_id: org.id)
      specimen = create(:specimen, owner_organization_id: org.id, source_organization_id: org.id)
      create(:planting_event, specimen: specimen, location: location)

      run(dry_run: false)

      expect(Specimen.where(id: specimen.id)).to be_empty
      expect(Location.where(id: location.id)).to be_empty
    end

    it 'reports a refusal rather than forcing it when something else still references the record' do
      org = unreachable_owner(purge_email)
      location = create(:location, owner_organization_id: org.id, source_organization_id: org.id)
      # An event belonging to somebody else's specimen still points at it.
      create(:planting_event, specimen: create(:specimen), location: location)

      expect { run(dry_run: false) }.to output(/REFUSED/).to_stdout
      expect(Location.where(id: location.id)).to be_present
    end
  end
end
