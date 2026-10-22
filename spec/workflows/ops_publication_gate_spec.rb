# frozen_string_literal: true

require 'rails_helper'
require 'open3'
require 'tmpdir'

# FPI plan API-15 (R2): negative tests for the ops-publication.yml safety
# gate. The gate is a script so it can be run here with good and bad inputs;
# the workflow examples below prove the apply job only runs on its verdict.
RSpec.describe 'ops-publication.yml safety gate' do
  let(:script) { Rails.root.join('.github/scripts/publication-gate.sh').to_s }
  let(:workflow) { YAML.safe_load_file(Rails.root.join('.github/workflows/ops-publication.yml')) }
  let(:digest) { 'a' * 64 }
  let(:apply_publish) do
    { 'TASK' => 'publish_wave', 'APPLY' => 'true', 'CONFIRM_APPLY' => 'PUBLISH-WAVE-APPLY',
      'EXPECTED_DIGEST' => digest, 'WAVE_KEY' => 'fpi-w1', 'SELECTOR' => 'quality' }
  end

  def gate(env)
    Dir.mktmpdir do |dir|
      output = File.join(dir, 'output')
      File.write(output, '')
      clean = %w[TASK APPLY CONFIRM_APPLY EXPECTED_DIGEST WAVE_KEY SELECTOR IDS LIMIT RULE].to_h { |k| [k, nil] }
      log, status = Open3.capture2e(clean.merge(env).merge('GITHUB_OUTPUT' => output), 'bash', script)
      { allowed: File.read(output).strip, ok: status.success?, log: log }
    end
  end

  it 'allows a confirmed publish_wave apply with the dry-run digest' do
    expect(gate(apply_publish)).to include(allowed: 'allowed=true', ok: true)
  end

  it 'allows every dry run without confirmation' do
    %w[report set_rule publish_wave unpublish_wave].each do |task|
      result = gate('TASK' => task, 'APPLY' => 'false', 'WAVE_KEY' => 'fpi-w1', 'RULE' => '{}')
      expect(result).to include(allowed: 'allowed=true', ok: true)
    end
  end

  it 'skips the apply on a wrong or missing confirm_apply' do
    ['', 'publish-wave-apply', 'RUN-FPI-APPLY', 'PUBLISH-WAVE-APPLY '].each do |confirm|
      result = gate(apply_publish.merge('CONFIRM_APPLY' => confirm))
      expect(result).to include(allowed: 'allowed=false', ok: false)
      expect(result[:log]).to include('confirm_apply')
    end
    expect(gate(apply_publish.except('CONFIRM_APPLY'))).to include(allowed: 'allowed=false', ok: false)
  end

  it 'skips a publish_wave apply without a well-formed expected_digest' do
    ['', 'abc', 'A' * 64, "#{digest}0"].each do |value|
      result = gate(apply_publish.merge('EXPECTED_DIGEST' => value))
      expect(result).to include(allowed: 'allowed=false', ok: false)
      expect(result[:log]).to include('expected_digest')
    end
    expect(gate(apply_publish.except('EXPECTED_DIGEST'))).to include(allowed: 'allowed=false', ok: false)
  end

  it 'needs no digest to apply unpublish_wave, but does need the confirmation' do
    unpublish = { 'TASK' => 'unpublish_wave', 'APPLY' => 'true', 'WAVE_KEY' => 'fpi-w1' }
    expect(gate(unpublish.merge('CONFIRM_APPLY' => 'PUBLISH-WAVE-APPLY'))).to include(ok: true)
    expect(gate(unpublish)).to include(allowed: 'allowed=false', ok: false)
  end

  it 'refuses other bad inputs' do
    expect(gate(apply_publish.merge('TASK' => 'drop_everything'))).to include(ok: false)
    expect(gate(apply_publish.merge('APPLY' => 'yes'))).to include(ok: false)
    expect(gate(apply_publish.merge('WAVE_KEY' => 'FPI W1'))).to include(ok: false)
    expect(gate(apply_publish.merge('SELECTOR' => 'all'))).to include(ok: false)
    expect(gate(apply_publish.merge('SELECTOR' => 'ids'))).to include(ok: false)
    expect(gate(apply_publish.merge('IDS' => 'x; rm -rf /'))).to include(ok: false)
    expect(gate(apply_publish.merge('LIMIT' => '-1'))).to include(ok: false)
    expect(gate('TASK' => 'report', 'APPLY' => 'true', 'CONFIRM_APPLY' => 'PUBLISH-WAVE-APPLY')).to include(ok: false)
    expect(gate('TASK' => 'set_rule', 'APPLY' => 'false')).to include(ok: false)
  end

  describe 'the workflow wiring' do
    let(:jobs) { workflow.fetch('jobs') }

    it 'runs the task only on the gate verdict' do
      expect(jobs['run-task']['needs']).to eq('gate')
      expect(jobs['run-task']['if']).to eq("needs.gate.outputs.allowed == 'true'")
      expect(jobs['gate']['outputs']).to eq('allowed' => '${{ steps.gate.outputs.allowed }}')
    end

    it 'runs the gate script with every input passed through the environment' do
      step = jobs['gate']['steps'].find { |s| s['id'] == 'gate' }
      expect(step['run']).to eq('bash .github/scripts/publication-gate.sh')
      expect(step['env']).to include('TASK' => '${{ inputs.task }}', 'APPLY' => '${{ inputs.apply }}',
                                     'CONFIRM_APPLY' => '${{ inputs.confirm_apply }}',
                                     'EXPECTED_DIGEST' => '${{ inputs.expected_digest }}')
    end

    it 'never interpolates an expression into a shell script' do
      scripts = jobs.values.flat_map { |job| job['steps'] }.filter_map { |s| s['run'] }
      scripts.each { |run| expect(run).not_to include('${{') }
    end

    it 'shares the FPI concurrency group and is dispatch-only' do
      expect(workflow['concurrency']).to eq('group' => 'ops-fpi-${{ inputs.environment }}', 'cancel-in-progress' => false)
      expect(workflow[true].keys).to eq(['workflow_dispatch']) # YAML 1.1 reads the key "on" as true
    end
  end
end
