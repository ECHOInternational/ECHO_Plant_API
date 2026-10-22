# frozen_string_literal: true

require 'rails_helper'
require 'rake'
require 'support/publication_wave_helpers'

# The publication:* tasks (API-14) and the counts-only rule (API-12, R2): this
# repository is public and so are the ops workflow logs, so nothing the tasks
# print may contain an email, a personal organization name or a principal.
RSpec.describe 'publication rake tasks', type: :task do
  include PublicationWaveHelpers

  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  let!(:rich) { source_plant(text: 600, owned_by: 'owner.person@example.org', created_by: 'creator.person@example.org') }
  let!(:pictured) { source_plant.tap { |p| plant_image(p, :private, created_by: 'uploader@example.org', owned_by: 'uploader@example.org') } }

  before do
    # A public twin owned by someone's personal organization (named after an
    # email, as 32 production personal organizations are) and an open draft.
    create(:plant, :public, scientific_name: rich.scientific_name, owned_by: 'twin.owner@example.org')
    author = create(:principal, email: 'draft.author@example.org', display_name: 'Draft Author Person')
    create(:record_draft, draftable: pictured, author_principal_id: author.id, last_editor_principal_id: author.id)
  end

  around do |example|
    keep = ENV.to_h.slice('APPLY', 'EXPECTED_DIGEST', 'SELECTOR', 'RULE', 'NOTES', 'SOURCE')
    example.run
  ensure
    %w[APPLY EXPECTED_DIGEST SELECTOR RULE NOTES SOURCE].each { |k| ENV.delete(k) }
    ENV.update(keep)
  end

  def run(name, *, **env)
    env.each { |k, v| ENV[k.to_s] = v }
    Rake::Task[name].reenable
    out = StringIO.new
    original = [$stdout, $stderr]
    $stdout = $stderr = out
    begin
      Rake::Task[name].invoke(*)
    rescue SystemExit
      nil
    ensure
      $stdout, $stderr = original
      env.each_key { |k| ENV.delete(k.to_s) }
    end
    out.string
  end

  # Every task once, in operator order; returns each task's printed output.
  def full_cycle_output
    wave_source # the data source must exist before the tasks look for it
    rule = PublicationWaveHelpers::WAVE_RULE.merge('min_text_chars' => 400).to_json
    outputs = [run('publication:report'), run('publication:set_rule', RULE: rule), run('publication:publish_wave', 'fpi-w1')]
    digest = outputs.last[/digest: (\h{64})/, 1]
    outputs + [
      run('publication:publish_wave', 'fpi-w1', APPLY: 'true', EXPECTED_DIGEST: digest, NOTES: 'first wave'),
      run('publication:report'),
      run('publication:unpublish_wave', 'fpi-w1'),
      run('publication:unpublish_wave', 'fpi-w1', APPLY: 'true'),
      run('publication:publish_wave', 'fpi-w2', APPLY: 'true', EXPECTED_DIGEST: 'f' * 64)
    ]
  end

  it 'runs a full dry run, apply, report and rollback cycle' do
    outputs = full_cycle_output
    expect(outputs[2]).to match(/DRY RUN wave fpi-w1/).and match(/plants\s+2$/).and match(/echo_twins\s+1$/)
      .and match(/open_drafts\s+1$/)
    expect(outputs[3]).to match(/PUBLISHED wave fpi-w1 \(applied\)/)
    expect(outputs[4]).to match(/wave fpi-w1: applied/)
    expect(outputs[6]).to match(/UNPUBLISHED wave fpi-w1 \(unpublished\)/)
    expect(outputs[7]).to match(/publish_wave refused: EXPECTED_DIGEST does not match/)
    expect(rich.reload.visibility).to eq('private')
  end

  it "prints counts only: no '@', no organization or principal name, nothing personal" do
    output = full_cycle_output.join("\n")
    expect(output).not_to include('@')
    names = Organization.pluck(:name) + Principal.pluck(:email, :display_name).flatten.compact
    expect(names).to include('twin.owner@example.org', 'Draft Author Person', 'Provider Org')
    names.each { |name| expect(output).not_to include(name) }
  end

  it 'refuses notes holding an email address before writing anything' do
    wave_source
    output = run('publication:publish_wave', 'fpi-w1', APPLY: 'true', EXPECTED_DIGEST: 'f' * 64, NOTES: 'for a@b.org')
    expect(output).to include("NOTES must not contain '@'")
    expect(PublicationWave.count).to eq(0)
  end

  it 'refuses an invalid rule' do
    wave_source
    output = run('publication:set_rule', RULE: '{"version":2}')
    expect(output).to include('rule refused')
    expect(wave_source.reload.publication_rule).to eq(PublicationWaveHelpers::WAVE_RULE)
  end
end
