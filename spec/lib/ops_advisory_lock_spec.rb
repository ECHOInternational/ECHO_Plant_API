# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OpsAdvisoryLock do
  let(:taken) { [] }

  after { taken.each(&:release) }

  def take(label)
    described_class.acquire!(label).tap { |lock| taken << lock }
  end

  it 'is taken by the first caller' do
    lock = take('first')
    expect(lock).to be_held
  end

  it 'refuses a second caller while the first holds it, even in the same process' do
    take('first')

    expect { described_class.acquire!('second') }
      .to raise_error(OpsAdvisoryLock::Held, /another ops write task is running.*second/m)
  end

  it 'can be taken again once released' do
    take('first').release
    expect(take('second')).to be_held
  end

  it 'tolerates a double release' do
    lock = take('first')
    lock.release
    expect { lock.release }.not_to raise_error
    expect(lock).not_to be_held
  end

  it 'is not tied to a surrounding transaction, so a rollback does not drop it' do
    ActiveRecord::Base.transaction do
      take('first')
      raise ActiveRecord::Rollback
    end

    expect { described_class.acquire!('second') }.to raise_error(OpsAdvisoryLock::Held)
  end
end
