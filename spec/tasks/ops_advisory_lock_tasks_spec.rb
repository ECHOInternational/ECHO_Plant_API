# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# API-20: every FPI write task takes one shared advisory lock, so two write
# tasks (a sync and a rollback, a rebaseline and an image import) can never
# interleave. GitHub's concurrency group is only a second layer: it keeps a
# single pending run per group and silently cancels an older one, so the lock
# is what actually guarantees mutual exclusion.
RSpec.describe 'ops advisory lock on FPI write tasks', type: :task do
  # task name => arguments the task accepts. The lock is taken before any
  # argument or data-source checks, so none of these need real data.
  write_tasks = {
    'fpi:bootstrap' => [],
    'fpi:sync_plants' => ['tmp/no-such-payload'],
    'fpi:resolve_conflicts' => ['tmp/no-such-rulings.json'],
    'fpi:rollback' => ['some-run'],
    'fpi:rebaseline' => [],
    'fpi:import_images' => ['tmp/no-such-manifest.json']
  }.freeze

  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  let(:holders) { [] }

  after { holders.each(&:release) }

  def hold_lock!
    OpsAdvisoryLock.acquire!('test holder').tap { |lock| holders << lock }
  end

  def quietly
    original = [$stdout, $stderr]
    $stdout = $stderr = StringIO.new
    yield
  ensure
    $stdout, $stderr = original
  end

  def run(name, args)
    Rake::Task[name].reenable
    Rake::Task[name].invoke(*args)
  end

  write_tasks.each do |name, args|
    describe name do
      it 'refuses to run while another session holds the ops lock' do
        hold_lock!

        expect { run(name, args) }
          .to raise_error(SystemExit) { |e| expect(e.status).not_to be_zero }
          .and output(/another ops write task is running/).to_stderr
      end

      it 'releases the lock when it finishes or aborts' do
        begin
          quietly { run(name, args) }
        rescue SystemExit
          # Aborting (missing data source, bad path) is a normal way to end.
          nil
        end

        holders << OpsAdvisoryLock.acquire!('after')
        expect(holders.last).to be_held
      end
    end
  end

  describe 'read-only tasks' do
    it 'fpi:preflight does not take the lock' do
      hold_lock!

      expect { run('fpi:preflight', ['tmp/no-such-payload']) }
        .to raise_error(SystemExit)
        .and output(/run fpi:bootstrap first|preflight FAILED/).to_stderr
    end
  end
end
