# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model do
  it 'can be instantiated' do
    user = build(:user)
    expect(user).to be_kind_of(User)
  end
  it 'is not persisted to the database' do
    user = build(:user)
    expect(user.persisted?).to be false
  end
  it 'responds to super_admin?' do
    user = build(:user)
    expect(user).to respond_to('super_admin?')
  end
  it 'is super administrator when plant permissions are high enough' do
    user = build(:user, trust_levels: { 'plant' => 10 })
    expect(user.super_admin?).to be true
  end
  it 'is not super administrator when plant permissions are not high enough' do
    user = build(:user, trust_levels: { 'plant' => 9 })
    expect(user.super_admin?).to be false
  end
  it 'responds to admin?' do
    user = build(:user)
    expect(user).to respond_to('admin?')
  end
  it 'is administrator when plant permissions are high enough' do
    user = build(:user, trust_levels: { 'plant' => 9 })
    expect(user.admin?).to be true
  end
  it 'is not administrator when plant permissions are not high enough' do
    user = build(:user, trust_levels: { 'plant' => 8 })
    expect(user.admin?).to be false
  end
  it 'responds to can_read?' do
    user = build(:user)
    expect(user).to respond_to('can_read?')
  end
  it 'can read when plant permissions are high enough' do
    user = build(:user, trust_levels: { 'plant' => 1 })
    expect(user.can_read?).to be true
  end
  it 'cannot read when plant permissions are not high enough' do
    user = build(:user, trust_levels: { 'plant' => 0 })
    expect(user.can_read?).to be false
  end
  it 'responds to can_write?' do
    user = build(:user)
    expect(user).to respond_to('can_write?')
  end
  it 'can write when plant permissions are high enough' do
    user = build(:user, trust_levels: { 'plant' => 2 })
    expect(user.can_write?).to be true
  end
  it 'cannot write when plant permissions are not high enough' do
    user = build(:user, trust_levels: { 'plant' => 1 })
    expect(user.can_write?).to be false
  end
end
