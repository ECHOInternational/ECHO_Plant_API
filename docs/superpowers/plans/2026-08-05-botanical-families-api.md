# Botanical Families (API) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a locked, Catalogue-of-Life-sourced `families` table with ECHO-owned editable metadata, relate every plant to one family, and expose it through GraphQL without changing any existing behaviour.

**Architecture:** `families` follows the *pure lookup* pattern (`tolerances`, `growth_habits`), not the *owned* pattern (`categories`): no ownership columns, no `OrganizedResource`, policy inheriting `ApplicationPolicy`. Immutability is enforced twice, in the model and by a database trigger, so it cannot be bypassed by `insert_all` or a console. `Plant belongs_to :family, optional: true`. The legacy `plants.family_names` string is left completely untouched.

**Tech Stack:** Rails 8.1.3, Ruby 3.4.10, PostgreSQL (UUID PKs via `pgcrypto`), graphql-ruby 2.3.23, `search_object_graphql` 1.0.5, Mobility (`:container` backend, single `translations` jsonb column), Pundit, RSpec + FactoryBot.

Design document: `docs/superpowers/specs/2026-08-05-botanical-families-design.md`. Read it before starting.

## Global Constraints

- **`db/structure.sql` is the real schema.** `db/schema.rb` is a stale 2020 artifact (`schema_format = :sql`). Never read or edit `schema.rb`.
- **ASCII only in Ruby COMMENTS** (`Style/AsciiComments`, on by default). String literals may and sometimes must contain non-ASCII: the reconciliation and seed-banking specs assert against real production values containing U+2013. `spec/mutations/update_variety_full_surface_spec.rb` already does this on a RuboCop-clean master.
- **`bundle exec rubocop` must report 0 offences.** It is a required check on master.
- **CI fails on GraphQL schema drift.** After any schema change run `bundle exec rails graphql:schema:dump` and commit `schema.graphql`.
- **Baseline is 1936 examples, 0 failures.** Never finish a task below that count.
- **Run the suite in the test environment explicitly:** `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec`. `.env` sets `RAILS_ENV=development` for the dev server.
- **Never modify `echocommunity-app`.** It is the frozen compatibility contract.
- **`spec/contracts/mobile_*` must pass untouched.** If a change requires editing them, the change is wrong.
- **Do not add a schema-wide `default_max_page_size` or `max_page_size` to `PlantApiSchema`.** The mobile `getAllPlants` query is unpaginated and a schema-wide cap would silently truncate its full sync. A **per-field** `max_page_size` on the new `Family.plants` connection is required and is not the same thing: it caps only a field no existing client calls.
- **Never change `Plant.family_names`**: same column, same type, same nullability, still writable, no `deprecation_reason`.
- **Factories stamp ownership.** `create(:plant, owned_by: user.email)` resolves a principal and personal organization via `spec/support/factory_ownership.rb`. Families has no ownership, so its factory must NOT stamp.
- **COL API needs a browser-like `User-Agent`**; bare requests are refused by a bot wall.
- **Pinned source:** ChecklistBank dataset `315834`, `COL26.7 XR`, snapshot date `2026-07-17`.

---

## File Structure

**Created**
- `db/migrate/20260805000001_create_families.rb` - table, indexes, immutability trigger
- `db/migrate/20260805000002_add_family_to_plants.rb` - `plants.family_id` + index + FK
- `app/models/family.rb` - model, Mobility, immutability guards, `.importing`
- `app/policies/family_policy.rb` - public read, update at trust 9, no create/destroy
- `app/graphql/types/family_type.rb` - the type
- `app/graphql/types/family_type/family_translation_type.rb`
- `app/graphql/types/family_type/family_edge_type.rb`
- `app/graphql/types/family_type/family_connection_with_total_count_type.rb`
- `app/graphql/resolvers/families_resolver.rb` - the collection query
- `app/graphql/mutations/update_family.rb` - metadata-only mutation
- `lib/catalogue_of_life.rb` - HTTP client for ChecklistBank
- `lib/family_name_normalizer.rb` - free-text cleaning (pure, no network)
- `lib/family_resolver.rb` - COL-first, GBIF-spelling-fallback resolution
- `lib/tasks/families.rake` - `seed`, `refresh`, `reconcile`, `load_seed_banking`
- `spec/factories/families.rb`
- Specs mirroring each of the above

**Modified**
- `app/models/plant.rb` - add `belongs_to :family, optional: true`
- `app/graphql/types/plant_type.rb` - add `field :family`
- `app/graphql/types/query_type.rb` - add `family` and `families`
- `app/graphql/types/mutation_type.rb` - add `update_family`
- `app/graphql/resolvers/plants_resolver.rb` - add `:family` to `includes`
- `app/graphql/mutations/create_plant.rb`, `update_plant.rb` - `family_id` argument + blank-only mirror
- `spec/factories/plants.rb` - leave `family_names`, do not add a default family
- `schema.graphql` - regenerated

---

### Task 1: Family model, table and immutability

**Files:**
- Create: `db/migrate/20260805000001_create_families.rb`
- Create: `app/models/family.rb`
- Create: `spec/factories/families.rb`
- Test: `spec/models/family_spec.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: `Family` with columns `name`, `col_id`, `kingdom`, `plant_type`, `status`, `superseded_by_id`, `classification_source`, `classification_version`, `snapshot_date`, `storage_physiology`, `seed_longevity`, `seed_banking_rank`; translated `description` and `seed_banking_notes`; class method `Family.importing { }`; scopes `Family.accepted`, `Family.superseded`.

- [ ] **Step 1: Write the failing model spec**

```ruby
# spec/models/family_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Family, type: :model do
  describe 'creation' do
    it 'is refused outside an importing block' do
      expect { create(:family) }.to raise_error(Family::ImmutableListError)
    end

    it 'is allowed inside an importing block' do
      family = described_class.importing { create(:family, name: 'Fabaceae') }
      expect(family).to be_persisted
      expect(family.name).to eq('Fabaceae')
    end
  end

  describe 'destruction' do
    it 'is refused outside an importing block' do
      family = described_class.importing { create(:family) }
      expect { family.destroy }.to raise_error(Family::ImmutableListError)
    end
  end

  describe 'metadata updates' do
    let(:family) { described_class.importing { create(:family, name: 'Fabaceae') } }

    it 'are allowed outside an importing block' do
      expect(family.update(seed_banking_rank: 5)).to be true
    end

    it 'translate the description' do
      Mobility.with_locale(:en) { family.description = 'Pea family' }
      Mobility.with_locale(:es) { family.description = 'Familia de los guisantes' }
      family.save!
      expect(family.translations['en']['description']).to eq('Pea family')
      expect(family.translations['es']['description']).to eq('Familia de los guisantes')
    end
  end

  describe 'validations' do
    subject(:family) { described_class.new(valid_attributes) }

    let(:valid_attributes) do
      { name: 'Fabaceae', kingdom: 'Plantae', classification_source: 'catalogue-of-life',
        classification_version: 'COL26.7 XR', snapshot_date: Date.new(2026, 7, 17) }
    end

    it { is_expected.to be_valid }

    it 'requires a name' do
      family.name = nil
      expect(family).not_to be_valid
    end

    it 'rejects a seed banking rank outside 1..5' do
      family.seed_banking_rank = 6
      expect(family).not_to be_valid
    end

    it 'rejects a duplicate name case-insensitively' do
      described_class.importing { described_class.create!(valid_attributes) }
      duplicate = described_class.new(valid_attributes.merge(name: 'fabaceae'))
      expect do
        described_class.importing { duplicate.save! }
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'scopes' do
    it 'separates accepted from superseded' do
      accepted, superseded = described_class.importing do
        [create(:family, name: 'Malvaceae'),
         create(:family, name: 'Tiliaceae', status: 'superseded')]
      end
      expect(described_class.accepted).to include(accepted)
      expect(described_class.accepted).not_to include(superseded)
      expect(described_class.superseded).to contain_exactly(superseded)
    end
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/models/family_spec.rb`
Expected: FAIL, `uninitialized constant Family`.

- [ ] **Step 3: Write the migration**

```ruby
# db/migrate/20260805000001_create_families.rb
# frozen_string_literal: true

class CreateFamilies < ActiveRecord::Migration[8.1]
  def change
    create_table :families, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :name, null: false
      t.string :col_id
      t.string :kingdom, null: false
      t.string :plant_type
      t.string :status, null: false, default: 'accepted'
      t.references :superseded_by, type: :uuid, foreign_key: { to_table: :families }
      t.string :classification_source, null: false
      t.string :classification_version, null: false
      t.date :snapshot_date, null: false
      t.string :storage_physiology
      t.string :seed_longevity
      t.integer :seed_banking_rank
      t.jsonb :translations, default: {}, null: false
      t.timestamps
    end

    add_index :families, 'lower(name)', unique: true, name: 'index_families_on_lower_name'
    add_index :families, :col_id, unique: true, where: 'col_id IS NOT NULL',
              name: 'index_families_on_col_id'
    add_index :families, :status
    add_index :families, :plant_type

    # Database-level immutability. The list may only be changed by the importer,
    # which sets families.import_mode for the duration of its transaction.
    # A model callback alone is not enough: insert_all, delete_all and a console
    # session all bypass it.
    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE FUNCTION families_reject_list_change() RETURNS trigger AS $$
          BEGIN
            IF current_setting('families.import_mode', true) IS DISTINCT FROM 'on' THEN
              RAISE EXCEPTION
                'families is a locked reference list; % is only permitted during an import',
                TG_OP;
            END IF;
            -- Permitted writes must proceed: returning NULL from a BEFORE row
            -- trigger would silently skip the row instead.
            RETURN COALESCE(NEW, OLD);
          END;
          $$ LANGUAGE plpgsql;

          CREATE TRIGGER families_locked_list
            BEFORE INSERT OR DELETE ON families
            FOR EACH ROW EXECUTE FUNCTION families_reject_list_change();
        SQL
      end
      dir.down do
        execute <<~SQL
          DROP TRIGGER IF EXISTS families_locked_list ON families;
          DROP FUNCTION IF EXISTS families_reject_list_change();
        SQL
      end
    end
  end
end
```

- [ ] **Step 4: Write the model**

```ruby
# app/models/family.rb
# frozen_string_literal: true

# A botanical, fungal or algal family, sourced from the Catalogue of Life.
#
# The LIST is locked: rows may only be created or destroyed by the importer,
# inside Family.importing. Everything ECHO adds on top (the translated
# description and the seed banking metadata) is ordinary editable data, gated
# at plant trust level 9 by FamilyPolicy.
#
# The natural key is `name`, not `col_id`. COL identifiers are documented as
# unstable and are forced to change whenever a name flips between accepted and
# synonym, which is exactly what happens when a family is merged. Family names
# do not change; their taxonomic status does.
class Family < ApplicationRecord
  # Raised when something tries to add to or remove from the locked list.
  class ImmutableListError < StandardError; end

  IMPORT_FLAG = 'families.import_mode'

  STORAGE_PHYSIOLOGIES = %w[orthodox recalcitrant intermediate variable mixed unknown].freeze
  SEED_LONGEVITIES = %w[low low_medium medium medium_high high].freeze
  STATUSES = %w[accepted superseded].freeze

  extend Mobility
  translates :description, :seed_banking_notes

  belongs_to :superseded_by, class_name: 'Family', optional: true
  has_many :plants, dependent: :nullify

  validates :name, :kingdom, :classification_source, :classification_version,
            :snapshot_date, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :storage_physiology, inclusion: { in: STORAGE_PHYSIOLOGIES }, allow_nil: true
  validates :seed_longevity, inclusion: { in: SEED_LONGEVITIES }, allow_nil: true
  validates :seed_banking_rank, inclusion: { in: 1..5 }, allow_nil: true

  scope :accepted, -> { where(status: 'accepted') }
  scope :superseded, -> { where(status: 'superseded') }

  before_create :assert_importing!
  before_destroy :assert_importing!

  class << self
    # The only context in which the list itself may change. Sets a Postgres
    # setting that the families_locked_list trigger checks, and a thread-local
    # that the model callbacks check, then restores both.
    #
    # The explicit reset in the ensure is load-bearing, not tidiness. A
    # transaction-local setting lives until the end of the ENCLOSING
    # transaction, and a nested `transaction` block joins the outer one rather
    # than scoping it. Under transactional test fixtures the enclosing
    # transaction is the whole example, so without this reset the list would
    # stay unlocked for the remainder of any example that imported once, and
    # the trigger specs would pass without proving anything.
    def importing
      previous = Thread.current[:family_importing]
      Thread.current[:family_importing] = true
      transaction do
        connection.execute("SELECT set_config('#{IMPORT_FLAG}', 'on', true)")
        yield
      end
    ensure
      Thread.current[:family_importing] = previous
      # Outside a transaction the setting is already gone with the commit, and
      # a local set_config would warn; only reset when one is still open.
      if connection.transaction_open?
        connection.execute("SELECT set_config('#{IMPORT_FLAG}', 'off', true)")
      end
    end

    def importing?
      Thread.current[:family_importing] == true
    end
  end

  private

  def assert_importing!
    return if self.class.importing?

    raise ImmutableListError,
          'families is a locked reference list; use Family.importing for imports'
  end
end
```

- [ ] **Step 5: Write the factory**

```ruby
# spec/factories/families.rb
# frozen_string_literal: true

# Deliberately does NOT stamp ownership. Family is reference data with no
# owner, unlike the five owned models covered by spec/support/factory_ownership.
FactoryBot.define do
  factory :family do
    sequence(:name) { |n| "Testaceae#{n}" }
    kingdom { 'Plantae' }
    plant_type { 'Angiosperms' }
    status { 'accepted' }
    classification_source { 'catalogue-of-life' }
    classification_version { 'COL26.7 XR' }
    snapshot_date { Date.new(2026, 7, 17) }
  end
end
```

- [ ] **Step 6: Migrate and run the spec**

Run:
```bash
docker compose run --rm -e RAILS_ENV=test web bundle exec rails db:migrate
docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/models/family_spec.rb
```
Expected: PASS, all examples green.

- [ ] **Step 7: Prove the database trigger, not just the callback**

Add to `spec/models/family_spec.rb`:

```ruby
  describe 'the database trigger' do
    it 'refuses a raw INSERT that bypasses the model' do
      expect do
        ActiveRecord::Base.connection.execute(<<~SQL)
          INSERT INTO families (name, kingdom, classification_source,
                                classification_version, snapshot_date,
                                created_at, updated_at)
          VALUES ('Sneakaceae', 'Plantae', 'manual', 'none', '2026-01-01',
                  now(), now())
        SQL
      end.to raise_error(ActiveRecord::StatementInvalid, /locked reference list/)
    end

    it 'refuses a raw DELETE that bypasses the model' do
      family = described_class.importing { create(:family) }
      expect do
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql(['DELETE FROM families WHERE id = ?', family.id])
        )
      end.to raise_error(ActiveRecord::StatementInvalid, /locked reference list/)
    end

    # Guards the reset in Family.importing's ensure block. A transaction-local
    # setting outlives the block it was set in, so without an explicit reset
    # the list would stay unlocked for the rest of the example and every
    # trigger assertion above would pass without proving anything.
    it 're-locks the list as soon as an importing block exits' do
      described_class.importing { create(:family, name: 'Firstaceae') }

      expect { create(:family, name: 'Secondaceae') }
        .to raise_error(described_class::ImmutableListError)

      expect do
        ActiveRecord::Base.connection.execute(<<~SQL)
          INSERT INTO families (name, kingdom, classification_source,
                                classification_version, snapshot_date,
                                created_at, updated_at)
          VALUES ('Thirdaceae', 'Plantae', 'manual', 'none', '2026-01-01',
                  now(), now())
        SQL
      end.to raise_error(ActiveRecord::StatementInvalid, /locked reference list/)
    end
  end
```

Run: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/models/family_spec.rb`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add db/migrate/20260805000001_create_families.rb db/structure.sql \
        app/models/family.rb spec/factories/families.rb spec/models/family_spec.rb
git commit -m "feat(families): locked family reference table with model and database guards"
```

---

### Task 2: FamilyPolicy

**Files:**
- Create: `app/policies/family_policy.rb`
- Test: `spec/policies/family_policy_spec.rb`

**Interfaces:**
- Consumes: `Family` from Task 1.
- Produces: `FamilyPolicy` with `index?`, `show?` true for everyone; `update?` true at plant trust >= 9; `create?` and `destroy?` inherited false.

- [ ] **Step 1: Write the failing policy spec**

```ruby
# spec/policies/family_policy_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FamilyPolicy, type: :policy do
  let(:target) { Family }

  context 'when no user is logged in' do
    let(:user) { nil }

    it { is_expected.to permit_action(:index) }
    it { is_expected.to permit_action(:show) }
    it { is_expected.to forbid_action(:create) }
    it { is_expected.to forbid_action(:update) }
    it { is_expected.to forbid_action(:destroy) }
  end

  context 'when the user has read-only access' do
    let(:user) { build(:user, :readonly) }

    it { is_expected.to permit_action(:show) }
    it { is_expected.to forbid_action(:update) }
  end

  context 'when the user has write access' do
    let(:user) { build(:user, :readwrite) }

    it { is_expected.to permit_action(:show) }
    it { is_expected.to forbid_action(:update) }
  end

  context 'when the user is an admin (trust 9)' do
    let(:user) { build(:user, :admin) }

    it { is_expected.to permit_action(:show) }
    it { is_expected.to permit_action(:update) }

    # The list itself stays immutable even for the people who edit its metadata.
    it { is_expected.to forbid_action(:create) }
    it { is_expected.to forbid_action(:destroy) }
  end

  context 'when the user is a super admin (trust 10)' do
    let(:user) { build(:user, :superadmin) }

    it { is_expected.to permit_action(:update) }
    it { is_expected.to forbid_action(:create) }
    it { is_expected.to forbid_action(:destroy) }
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/policies/family_policy_spec.rb`
Expected: FAIL, `uninitialized constant FamilyPolicy`.

- [ ] **Step 3: Write the policy**

```ruby
# app/policies/family_policy.rb
# frozen_string_literal: true

# Security policy for Family objects.
#
# Families is a locked reference list sourced from the Catalogue of Life. The
# LIST is immutable through the API: create? and destroy? are deliberately not
# defined here, so they inherit ApplicationPolicy's false. That is the whole
# point, and it is why this does not subclass OwnedResourcePolicy, whose
# create? grants creation to any trust-2 writer.
#
# The METADATA that ECHO layers on top (description, seed banking fields) is
# editable at trust level 9. That is deliberately lower than the other lookup
# tables, which require 10: their lists are editable, so a low bar would let
# anyone fork the vocabulary. Here the vocabulary cannot be forked at all, so
# only the annotations are at stake. Trust 10 also currently has no members,
# which would make metadata uneditable by anyone.
class FamilyPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def update?
    user&.admin?
  end
end
```

- [ ] **Step 4: Run the spec**

Run: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/policies/family_policy_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/policies/family_policy.rb spec/policies/family_policy_spec.rb
git commit -m "feat(families): public read, metadata editable at trust 9, list immutable"
```

---

### Task 3: The plant to family relation

**Files:**
- Create: `db/migrate/20260805000002_add_family_to_plants.rb`
- Modify: `app/models/plant.rb`
- Test: `spec/models/plant_spec.rb` (append)

**Interfaces:**
- Consumes: `Family` from Task 1.
- Produces: `plants.family_id` (nullable uuid, FK); `Plant#family` / `Plant#family=`; `Family#plants`.

- [ ] **Step 1: Write the failing relation spec**

Append to `spec/models/plant_spec.rb`:

```ruby
  describe 'family relation' do
    let(:family) { Family.importing { create(:family, name: 'Fabaceae') } }

    it 'is optional' do
      plant = create(:plant, family: nil)
      expect(plant).to be_valid
      expect(plant.family).to be_nil
    end

    it 'links a plant to exactly one family' do
      plant = create(:plant, family: family)
      expect(plant.reload.family).to eq(family)
      expect(family.plants).to include(plant)
    end

    it 'nullifies the plant link rather than blocking when a family is removed' do
      plant = create(:plant, family: family)
      Family.importing { family.destroy }
      expect(plant.reload.family_id).to be_nil
    end
  end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/models/plant_spec.rb -e "family relation"`
Expected: FAIL, unknown attribute `family`.

- [ ] **Step 3: Write the migration**

```ruby
# db/migrate/20260805000002_add_family_to_plants.rb
# frozen_string_literal: true

class AddFamilyToPlants < ActiveRecord::Migration[8.1]
  def change
    add_reference :plants, :family, type: :uuid, null: true, foreign_key: true,
                                    index: { name: 'index_plants_on_family_id' }
  end
end
```

- [ ] **Step 4: Add the association to Plant**

In `app/models/plant.rb`, alongside the other associations:

```ruby
  # One family per plant. The legacy free-text family_names column is left
  # untouched and still writable; see the families design document.
  belongs_to :family, optional: true
```

- [ ] **Step 5: Migrate and run**

Run:
```bash
docker compose run --rm -e RAILS_ENV=test web bundle exec rails db:migrate
docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/models/plant_spec.rb
```
Expected: PASS, including all pre-existing plant examples.

- [ ] **Step 6: Commit**

```bash
git add db/migrate/20260805000002_add_family_to_plants.rb db/structure.sql \
        app/models/plant.rb spec/models/plant_spec.rb
git commit -m "feat(families): relate each plant to at most one family"
```

---

### Task 4: GraphQL type and its subtypes

**Files:**
- Create: `app/graphql/types/family_type.rb`
- Create: `app/graphql/types/family_type/family_translation_type.rb`
- Create: `app/graphql/types/family_type/family_edge_type.rb`
- Create: `app/graphql/types/family_type/family_connection_with_total_count_type.rb`
- Modify: `app/models/family.rb` (add `translations_array`)
- Test: `spec/models/family_spec.rb` (append)

**Interfaces:**
- Consumes: `Family`.
- Produces: `Types::FamilyType` exposing `id` (Relay global), `uuid`, `name`, `kingdom`, `plantType`, `status`, `colId`, `classificationVersion`, `snapshotDate`, `description`, `seedBankingNotes`, `storagePhysiology`, `seedLongevity`, `seedBankingRank`, `translations`; plus the connection type used by Task 5.

- [ ] **Step 1: Write the failing translations_array spec**

Append to `spec/models/family_spec.rb`:

```ruby
  describe '#translations_array' do
    it 'flattens the Mobility container into per-locale rows' do
      family = described_class.importing { create(:family) }
      Mobility.with_locale(:en) do
        family.description = 'Pea family'
        family.seed_banking_notes = 'Highly suitable'
      end
      family.save!

      row = family.translations_array.find { |t| t[:locale] == 'en' }
      expect(row[:description]).to eq('Pea family')
      expect(row[:seed_banking_notes]).to eq('Highly suitable')
    end
  end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/models/family_spec.rb -e translations_array`
Expected: FAIL, undefined method `translations_array`.

- [ ] **Step 3: Add translations_array to the model**

In `app/models/family.rb`, above the `private` keyword:

```ruby
  def translations_array
    translations.map do |language, attributes|
      {
        locale: language,
        description: attributes['description'],
        seed_banking_notes: attributes['seed_banking_notes']
      }
    end
  end
```

- [ ] **Step 4: Write the four type files**

```ruby
# app/graphql/types/family_type.rb
# frozen_string_literal: true

module Types
  # Defines fields for a botanical, fungal or algal family.
  class FamilyType < Types::BaseObject
    global_id_field :id
    implements GraphQL::Types::Relay::Node

    description 'A family is a rank of biological classification, sourced from ' \
                'the Catalogue of Life. The list is fixed; only its metadata is editable.'

    field :uuid, ID,
          description: 'The internal database ID for a family',
          null: false,
          method: :id
    field :name, String,
          description: 'The scientific name of the family. Not translated.',
          null: false
    field :kingdom, String,
          description: 'Plantae, Fungi or Chromista',
          null: false
    field :plant_type, String,
          description: 'Broad grouping derived from the source classification, ' \
                       'for example Angiosperms or Ferns & Fern Allies',
          null: true
    field :status, String,
          description: 'accepted, or superseded when the source taxonomy has merged ' \
                       'this family into another',
          null: false
    field :superseded_by, Types::FamilyType,
          description: 'The family this one was merged into, when status is superseded',
          null: true
    field :col_id, String,
          description: 'Catalogue of Life identifier. Informational only: these are ' \
                       'not stable across releases and nothing references them.',
          null: true
    field :classification_version, String,
          description: 'The source release this row was loaded from',
          null: false
    field :snapshot_date, GraphQL::Types::ISO8601Date,
          description: 'The date of the source release',
          null: false

    field :description, String,
          description: 'The translated description of a family',
          null: true
    field :seed_banking_notes, String,
          description: 'Translated notes on this family suitability for seed banking',
          null: true
    field :storage_physiology, String,
          description: 'orthodox, recalcitrant, intermediate, variable, mixed or unknown',
          null: true
    field :seed_longevity, String,
          description: 'low, low_medium, medium, medium_high or high',
          null: true
    field :seed_banking_rank, Integer,
          description: 'Seed banking suitability from 1 (poor) to 5 (excellent)',
          null: true

    field :translations, [Types::FamilyType::FamilyTranslationType],
          description: 'Translations of translatable family fields',
          null: false,
          method: :translations_array
  end
end
```

```ruby
# app/graphql/types/family_type/family_translation_type.rb
# frozen_string_literal: true

module Types
  class FamilyType
    # Translated fields for a family
    class FamilyTranslationType < Types::BaseObject
      description 'Translated fields for a family'

      field :locale, String,
            description: 'The locale for this translation',
            null: false
      field :description, String,
            description: 'The translated description of a family',
            null: true
      field :seed_banking_notes, String,
            description: 'The translated seed banking notes for a family',
            null: true
    end
  end
end
```

```ruby
# app/graphql/types/family_type/family_edge_type.rb
# frozen_string_literal: true

module Types
  class FamilyType
    class FamilyEdgeType < GraphQL::Types::Relay::BaseEdge
      node_type(Types::FamilyType)
    end
  end
end
```

```ruby
# app/graphql/types/family_type/family_connection_with_total_count_type.rb
# frozen_string_literal: true

module Types
  class FamilyType
    class FamilyConnectionWithTotalCountType < GraphQL::Types::Relay::BaseConnection
      edge_type(FamilyEdgeType)

      field :total_count, Integer, null: false
      def total_count
        object.items.size
      end
    end
  end
end
```

Note this references `Types::FamilyType::FamilyTranslationType`, its own type. Two
existing lookups (`growth_habit_type.rb`, `image_attribute_type.rb`) mistakenly
reference `Types::CategoryType::CategoryTranslationType` instead of their own.
Do not repeat that.

- [ ] **Step 5: Run the model spec**

Run: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/models/family_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/graphql/types/family_type.rb app/graphql/types/family_type/ \
        app/models/family.rb spec/models/family_spec.rb
git commit -m "feat(families): GraphQL type, translation, edge and connection types"
```

---

### Task 5: The family and families queries

**Files:**
- Create: `app/graphql/resolvers/families_resolver.rb`
- Modify: `app/graphql/types/query_type.rb`
- Test: `spec/queries/family_query_spec.rb`, `spec/queries/families_query_spec.rb`

**Interfaces:**
- Consumes: `Types::FamilyType` and its connection type from Task 4.
- Produces: query fields `family(id:, language:)` and `families(name:, kingdom:, plantType:, language:, first:, after:)`.

- [ ] **Step 1: Write the failing query specs**

```ruby
# spec/queries/families_query_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'families query', type: :request do
  before do
    Family.importing do
      create(:family, name: 'Fabaceae', kingdom: 'Plantae', plant_type: 'Angiosperms')
      create(:family, name: 'Poaceae', kingdom: 'Plantae', plant_type: 'Angiosperms')
      create(:family, name: 'Russulaceae', kingdom: 'Fungi', plant_type: 'Fungi')
    end
  end

  def execute(query)
    PlantApiSchema.execute(query, context: { current_user: nil })
  end

  it 'is readable without a token and reports a total count' do
    result = execute('{ families(first: 10) { totalCount nodes { name } } }')
    expect(result['errors']).to be_nil
    expect(result.dig('data', 'families', 'totalCount')).to eq(3)
  end

  it 'orders by name so paging is stable' do
    result = execute('{ families(first: 10) { nodes { name } } }')
    names = result.dig('data', 'families', 'nodes').map { |n| n['name'] }
    expect(names).to eq(%w[Fabaceae Poaceae Russulaceae])
  end

  it 'filters by a case-insensitive partial name' do
    result = execute('{ families(first: 10, name: "acea") { totalCount } }')
    expect(result.dig('data', 'families', 'totalCount')).to eq(3)
  end

  it 'filters by kingdom' do
    result = execute('{ families(first: 10, kingdom: "Fungi") { nodes { name } } }')
    expect(result.dig('data', 'families', 'nodes').map { |n| n['name'] }).to eq(['Russulaceae'])
  end

  it 'filters by plant type' do
    result = execute('{ families(first: 10, plantType: "Angiosperms") { totalCount } }')
    expect(result.dig('data', 'families', 'totalCount')).to eq(2)
  end

  it 'excludes superseded families by default' do
    Family.importing { create(:family, name: 'Tiliaceae', status: 'superseded') }
    result = execute('{ families(first: 10) { totalCount } }')
    expect(result.dig('data', 'families', 'totalCount')).to eq(3)
  end
end
```

```ruby
# spec/queries/family_query_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'family query', type: :request do
  let!(:family) do
    Family.importing do
      record = create(:family, name: 'Fabaceae')
      Mobility.with_locale(:en) { record.description = 'Pea family' }
      Mobility.with_locale(:es) { record.description = 'Familia de las leguminosas' }
      record.save!
      record
    end
  end

  let(:global_id) { PlantApiSchema.id_from_object(family, Family, {}) }

  def execute(query, variables = {})
    PlantApiSchema.execute(query, variables: variables, context: { current_user: nil })
  end

  it 'loads a family by its Relay global id' do
    result = execute(<<~GQL, { 'id' => global_id })
      query($id: ID!) { family(id: $id) { name kingdom description } }
    GQL
    expect(result.dig('data', 'family', 'name')).to eq('Fabaceae')
    expect(result.dig('data', 'family', 'description')).to eq('Pea family')
  end

  it 'honours the language argument' do
    result = execute(<<~GQL, { 'id' => global_id })
      query($id: ID!) { family(id: $id, language: "es") { description } }
    GQL
    expect(result.dig('data', 'family', 'description')).to eq('Familia de las leguminosas')
  end

  it 'returns the full translations array' do
    result = execute(<<~GQL, { 'id' => global_id })
      query($id: ID!) { family(id: $id) { translations { locale description } } }
    GQL
    locales = result.dig('data', 'family', 'translations').map { |t| t['locale'] }
    expect(locales).to contain_exactly('en', 'es')
  end
end
```

- [ ] **Step 2: Run and confirm failure**

Run: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/queries/families_query_spec.rb spec/queries/family_query_spec.rb`
Expected: FAIL, `Field 'families' doesn't exist on type 'Query'`.

- [ ] **Step 3: Write the resolver**

```ruby
# app/graphql/resolvers/families_resolver.rb
# frozen_string_literal: true

require 'search_object'
require 'search_object/plugin/graphql'

module Resolvers
  # Populates the data for the families Query
  class FamiliesResolver < Resolvers::BaseResolver
    include SearchObject.module(:graphql)
    type Types::FamilyType::FamilyConnectionWithTotalCountType, null: false
    description 'Returns a list of Families'

    # Ordered by the untranslated scientific name, so unlike the other lookups
    # this does not need the .i18n scope for ordering. id breaks ties so the
    # offset-paginated connection cannot skip or repeat a row between pages.
    scope { Family.accepted.order(name: :asc).order(id: :asc) }

    option :language,
           type: String,
           with: :apply_language_filter,
           description: 'Request returned fields in a specific language. Overrides ACCEPT-LANGUAGE header.'
    option :name,
           type: String,
           with: :apply_name_filter,
           description: 'Performs a case-insensitive LIKE match on the scientific name'
    option :kingdom,
           type: String,
           with: :apply_kingdom_filter,
           description: 'Restrict to one of Plantae, Fungi or Chromista'
    option :plant_type,
           type: String,
           with: :apply_plant_type_filter,
           description: 'Restrict to a broad grouping such as Angiosperms or Fungi'

    def apply_name_filter(scope, value)
      return scope if value.blank?

      scope.where('families.name ILIKE ?', "%#{value}%")
    end

    def apply_kingdom_filter(scope, value)
      return scope if value.blank?

      scope.where(kingdom: value)
    end

    def apply_plant_type_filter(scope, value)
      return scope if value.blank?

      scope.where(plant_type: value)
    end

    def apply_language_filter(scope, _value)
      # the language is actually applied in the fetch results method
      scope
    end

    def fetch_results
      Mobility.locale = language if language
      super
    end
  end
end
```

- [ ] **Step 4: Wire both queries into QueryType**

In `app/graphql/types/query_type.rb`, beside the other lookup collection fields:

```ruby
    field :families, resolver: Resolvers::FamiliesResolver, connection: true
```

and beside the other single-object lookups:

```ruby
    field :family, Types::FamilyType, null: true do
      description 'Find a family by ID'
      argument :id,
               type: ID,
               required: true
      argument :language,
               type: String,
               required: false,
               description: 'Request returned fields in a specific language. Overrides ACCEPT-LANGUAGE header.'
    end
    def family(id:, language: nil)
      item_id = decode_global_id(id)
      Mobility.locale = language || I18n.locale
      Family.find(item_id)
    end
```

Like the other pure lookups, this uses a plain `find` rather than
`Pundit.policy_scope`, because families are unconditionally public and carry no
visibility column. Families does not need adding to `NODE_POLICY_SCOPED` for the
same reason.

- [ ] **Step 5: Run the specs**

Run: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/queries/families_query_spec.rb spec/queries/family_query_spec.rb`
Expected: PASS.

- [ ] **Step 6: Regenerate the schema and commit**

```bash
docker compose run --rm -e RAILS_ENV=test web bundle exec rails graphql:schema:dump
git add app/graphql/resolvers/families_resolver.rb app/graphql/types/query_type.rb \
        schema.graphql spec/queries/family_query_spec.rb spec/queries/families_query_spec.rb
git commit -m "feat(families): family and families queries"
```

---

### Task 6: Plant.family and Family.plants

**Files:**
- Modify: `app/graphql/types/plant_type.rb`
- Modify: `app/graphql/types/family_type.rb`
- Modify: `app/graphql/resolvers/plants_resolver.rb`
- Test: `spec/queries/family_plants_query_spec.rb`

**Interfaces:**
- Consumes: Tasks 3, 4, 5.
- Produces: `Plant.family` returning `FamilyType`; `Family.plants` returning a policy-scoped, page-capped plant connection.

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/queries/family_plants_query_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'family plants', type: :request do
  let(:family) { Family.importing { create(:family, name: 'Fabaceae') } }
  let!(:public_plant) { create(:plant, :public, family: family, scientific_name: 'Vigna unguiculata') }
  let!(:private_plant) { create(:plant, :private, family: family, scientific_name: 'Secret bean') }

  let(:global_id) { PlantApiSchema.id_from_object(family, Family, {}) }

  def execute(query, user)
    PlantApiSchema.execute(query, variables: { 'id' => global_id },
                                  context: { current_user: user })
  end

  it 'lists only public plants for an anonymous caller' do
    result = execute(<<~GQL, nil)
      query($id: ID!) { family(id: $id) { plants(first: 10) { totalCount nodes { scientificName } } } }
    GQL
    names = result.dig('data', 'family', 'plants', 'nodes').map { |n| n['scientificName'] }
    expect(names).to eq(['Vigna unguiculata'])
    expect(result.dig('data', 'family', 'plants', 'totalCount')).to eq(1)
  end

  it 'exposes the family from the plant side' do
    plant_id = PlantApiSchema.id_from_object(public_plant, Plant, {})
    result = PlantApiSchema.execute(<<~GQL, variables: { 'id' => plant_id }, context: { current_user: nil })
      query($id: ID!) { plant(id: $id) { family { name } familyNames } }
    GQL
    expect(result.dig('data', 'plant', 'family', 'name')).to eq('Fabaceae')
  end

  it 'returns a null family when the plant has none' do
    orphan = create(:plant, :public, family: nil)
    plant_id = PlantApiSchema.id_from_object(orphan, Plant, {})
    result = PlantApiSchema.execute(<<~GQL, variables: { 'id' => plant_id }, context: { current_user: nil })
      query($id: ID!) { plant(id: $id) { family { name } } }
    GQL
    expect(result.dig('data', 'plant', 'family')).to be_nil
  end
end
```

- [ ] **Step 2: Run and confirm failure**

Run: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/queries/family_plants_query_spec.rb`
Expected: FAIL, `Field 'plants' doesn't exist on type 'Family'`.

- [ ] **Step 3: Add the plants connection to FamilyType**

In `app/graphql/types/family_type.rb`, after the `translations` field:

```ruby
    # Fabaceae alone will eventually hold roughly 2,200 plants once the Food
    # Plants International import lands. A per-field cap is used rather than a
    # schema-wide default_max_page_size, because the frozen mobile client calls
    # plants() with no first: argument and a global cap would silently truncate
    # its full sync.
    field :plants, Types::PlantType::PlantConnectionWithTotalCountType,
          description: 'The plants belonging to this family',
          null: false,
          connection: true,
          max_page_size: 100

    def plants
      Pundit.policy_scope(context[:current_user], object.plants).i18n
    end
```

- [ ] **Step 4: Add the family field to PlantType**

In `app/graphql/types/plant_type.rb`, beside `family_names`:

```ruby
    field :family, Types::FamilyType,
          description: 'The botanical family this plant belongs to',
          null: true
```

No resolver method is needed: it is a real `belongs_to`, so graphql-ruby calls
`object.family`. Families are unconditionally public, so no policy scoping
applies.

- [ ] **Step 5: Preload the association in PlantsResolver**

In `app/graphql/resolvers/plants_resolver.rb`, extend the existing `includes`:

```ruby
    scope { Pundit.policy_scope(context[:current_user], Plant).i18n.includes(:common_names, :varieties, :family) }
```

- [ ] **Step 6: Run the spec and the plant query suite**

Run:
```bash
docker compose run --rm -e RAILS_ENV=test web bundle exec rspec \
  spec/queries/family_plants_query_spec.rb spec/queries/ spec/contracts/
```
Expected: PASS, contracts included.

- [ ] **Step 7: Regenerate the schema and commit**

```bash
docker compose run --rm -e RAILS_ENV=test web bundle exec rails graphql:schema:dump
git add app/graphql/types/family_type.rb app/graphql/types/plant_type.rb \
        app/graphql/resolvers/plants_resolver.rb schema.graphql \
        spec/queries/family_plants_query_spec.rb
git commit -m "feat(families): expose family on plants and plants on a family"
```

---

### Task 7: The updateFamily mutation

**Files:**
- Create: `app/graphql/mutations/update_family.rb`
- Modify: `app/graphql/types/mutation_type.rb`
- Test: `spec/mutations/update_family_spec.rb`

**Interfaces:**
- Consumes: `Family`, `FamilyPolicy`, `Types::FamilyType`.
- Produces: mutation `updateFamily(input: { familyId, description, seedBankingNotes, storagePhysiology, seedLongevity, seedBankingRank, language })` returning `{ family, errors }`.

- [ ] **Step 1: Write the failing mutation spec**

```ruby
# spec/mutations/update_family_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'updateFamily mutation', type: :request do
  let(:family) { Family.importing { create(:family, name: 'Fabaceae') } }
  let(:global_id) { PlantApiSchema.id_from_object(family, Family, {}) }

  let(:query) do
    <<~GQL
      mutation($input: UpdateFamilyInput!) {
        updateFamily(input: $input) {
          family { name description seedBankingRank storagePhysiology seedLongevity }
          errors { field message code }
        }
      }
    GQL
  end

  def execute(user, input = {})
    PlantApiSchema.execute(
      query,
      variables: { 'input' => { 'familyId' => global_id }.merge(input) },
      context: { current_user: user }
    )
  end

  it 'rejects an anonymous caller with 401' do
    result = execute(nil, { 'description' => 'nope' })
    expect(result.dig('errors', 0, 'extensions', 'code')).to eq(401)
  end

  it 'rejects a trust-2 writer with 403' do
    result = execute(build(:user, :readwrite), { 'description' => 'nope' })
    expect(result.dig('errors', 0, 'extensions', 'code')).to eq(403)
  end

  it 'allows a trust-9 admin to edit the description' do
    result = execute(build(:user, :admin), { 'description' => 'Pea family' })
    expect(result['errors']).to be_nil
    expect(result.dig('data', 'updateFamily', 'family', 'description')).to eq('Pea family')
  end

  it 'writes the description into the requested locale' do
    execute(build(:user, :admin), { 'description' => 'Familia de las leguminosas', 'language' => 'es' })
    expect(family.reload.translations['es']['description']).to eq('Familia de las leguminosas')
  end

  it 'edits the seed banking metadata' do
    result = execute(build(:user, :admin),
                     { 'seedBankingRank' => 5, 'storagePhysiology' => 'orthodox',
                       'seedLongevity' => 'high' })
    data = result.dig('data', 'updateFamily', 'family')
    expect(data['seedBankingRank']).to eq(5)
    expect(data['storagePhysiology']).to eq('orthodox')
    expect(data['seedLongevity']).to eq('high')
  end

  it 'returns a payload error for an out-of-range rank' do
    result = execute(build(:user, :admin), { 'seedBankingRank' => 9 })
    expect(result.dig('data', 'updateFamily', 'errors', 0, 'code')).to eq(400)
    expect(family.reload.seed_banking_rank).to be_nil
  end

  it 'returns a payload error for an unknown storage physiology' do
    result = execute(build(:user, :admin), { 'storagePhysiology' => 'squishy' })
    expect(result.dig('data', 'updateFamily', 'errors', 0, 'code')).to eq(400)
  end

  # The list is immutable: identity is not editable at any trust level.
  it 'has no argument that could rename a family' do
    input_type = PlantApiSchema.types['UpdateFamilyInput']
    expect(input_type.arguments.keys).not_to include('name', 'colId', 'kingdom')
  end
end
```

- [ ] **Step 2: Run and confirm failure**

Run: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/mutations/update_family_spec.rb`
Expected: FAIL, `UpdateFamilyInput` is not defined.

- [ ] **Step 3: Write the mutation**

```ruby
# app/graphql/mutations/update_family.rb
# frozen_string_literal: true

module Mutations
  # Updates the metadata ECHO layers on top of the locked family list.
  #
  # This deliberately does NOT use Mutations::Lookups::UpdateLookupBaseMutation.
  # Those base classes come as a create/update/delete trio and their shared spec
  # generator assumes all three exist; adopting them would hand us exactly the
  # create and delete mutations that must not exist for families.
  #
  # There is no name, colId or kingdom argument. The list is fixed; only the
  # annotations are editable.
  class UpdateFamily < BaseMutation
    argument :family_id, GraphQL::Types::ID,
             required: true,
             loads: Types::FamilyType,
             description: 'The family whose metadata is being edited'
    argument :description, String,
             required: false,
             description: 'Translatable description of the family'
    argument :seed_banking_notes, String,
             required: false,
             description: 'Translatable notes on seed banking suitability'
    argument :storage_physiology, String,
             required: false,
             description: 'orthodox, recalcitrant, intermediate, variable, mixed or unknown'
    argument :seed_longevity, String,
             required: false,
             description: 'low, low_medium, medium, medium_high or high'
    argument :seed_banking_rank, Integer,
             required: false,
             description: 'Seed banking suitability from 1 (poor) to 5 (excellent)'
    argument :language, String,
             required: false,
             description: 'Language of the translatable fields supplied'

    field :family, Types::FamilyType, null: true
    field :errors, [Types::MutationError], null: false

    TRANSLATED = %i[description seed_banking_notes].freeze
    PLAIN = %i[storage_physiology seed_longevity seed_banking_rank].freeze

    def authorized?(**attributes)
      authorize attributes[:family], :update?
    end

    def resolve(**attributes)
      family = attributes[:family]
      language = attributes[:language] || I18n.locale

      Mobility.with_locale(language) do
        TRANSLATED.each { |key| family.public_send("#{key}=", attributes[key]) if attributes.key?(key) }
        PLAIN.each { |key| family.public_send("#{key}=", attributes[key]) if attributes.key?(key) }
        family.save

        {
          family: family,
          errors: errors_from_active_record(family.errors)
        }
      end
    end
  end
end
```

- [ ] **Step 4: Wire it into MutationType**

In `app/graphql/types/mutation_type.rb`:

```ruby
    field :update_family, mutation: Mutations::UpdateFamily,
                          description: 'Updates the editable metadata on a family'
```

There is deliberately no `create_family` and no `delete_family`.

- [ ] **Step 5: Run the spec**

Run: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/mutations/update_family_spec.rb`
Expected: PASS.

- [ ] **Step 6: Assert the absence of list mutations**

Create `spec/mutations/family_list_immutability_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'the family list is immutable through GraphQL', type: :request do
  let(:mutation_fields) { PlantApiSchema.mutation.fields.keys }

  it 'exposes no mutation that creates a family' do
    expect(mutation_fields).not_to include('createFamily')
  end

  it 'exposes no mutation that deletes a family' do
    expect(mutation_fields).not_to include('deleteFamily')
  end

  it 'exposes exactly one family mutation' do
    expect(mutation_fields.grep(/[Ff]amily/)).to eq(['updateFamily'])
  end
end
```

Run: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/mutations/`
Expected: PASS.

- [ ] **Step 7: Regenerate the schema and commit**

```bash
docker compose run --rm -e RAILS_ENV=test web bundle exec rails graphql:schema:dump
git add app/graphql/mutations/update_family.rb app/graphql/types/mutation_type.rb \
        schema.graphql spec/mutations/update_family_spec.rb \
        spec/mutations/family_list_immutability_spec.rb
git commit -m "feat(families): metadata-only updateFamily mutation at trust 9"
```

---

### Task 8: Setting a plant family, and the blank-only mirror

**Files:**
- Modify: `app/graphql/mutations/create_plant.rb`
- Modify: `app/graphql/mutations/update_plant.rb`
- Test: `spec/mutations/plant_family_assignment_spec.rb`

**Interfaces:**
- Consumes: Tasks 3 and 4.
- Produces: `familyId` argument on both plant mutations; `family_names` mirrored from the family name only when it is blank.

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/mutations/plant_family_assignment_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'assigning a family to a plant', type: :request do
  let(:user) { build(:user, :readwrite) }
  let(:family) { Family.importing { create(:family, name: 'Fabaceae') } }
  let(:family_gid) { PlantApiSchema.id_from_object(family, Family, {}) }

  let(:query) do
    <<~GQL
      mutation($input: UpdatePlantInput!) {
        updatePlant(input: $input) {
          plant { familyNames family { name } }
          errors { field message code }
        }
      }
    GQL
  end

  def update(plant, input)
    PlantApiSchema.execute(
      query,
      variables: { 'input' => {
        'plantId' => PlantApiSchema.id_from_object(plant, Plant, {})
      }.merge(input) },
      context: { current_user: user }
    )
  end

  it 'links the family' do
    plant = create(:plant, owned_by: user.email, family_names: nil)
    result = update(plant, { 'familyId' => family_gid })
    expect(result.dig('data', 'updatePlant', 'plant', 'family', 'name')).to eq('Fabaceae')
  end

  it 'mirrors the family name into a BLANK familyNames' do
    plant = create(:plant, owned_by: user.email, family_names: nil)
    update(plant, { 'familyId' => family_gid })
    expect(plant.reload.family_names).to eq('Fabaceae')
  end

  it 'mirrors into an empty-string familyNames' do
    plant = create(:plant, owned_by: user.email, family_names: '   ')
    update(plant, { 'familyId' => family_gid })
    expect(plant.reload.family_names).to eq('Fabaceae')
  end

  # The single most important guarantee in this task: a human typed that text.
  it 'NEVER overwrites a populated familyNames' do
    plant = create(:plant, owned_by: user.email, family_names: 'Leguminosae - Pea')
    update(plant, { 'familyId' => family_gid })
    expect(plant.reload.family_names).to eq('Leguminosae - Pea')
  end

  it 'leaves familyNames writable on its own, with no family set' do
    plant = create(:plant, owned_by: user.email, family_names: 'Whatever the user typed')
    update(plant, { 'familyNames' => 'Still free text' })
    expect(plant.reload.family_names).to eq('Still free text')
    expect(plant.reload.family_id).to be_nil
  end
end
```

- [ ] **Step 2: Run and confirm failure**

Run: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/mutations/plant_family_assignment_spec.rb`
Expected: FAIL, `familyId` is not defined on `UpdatePlantInput`.

- [ ] **Step 3: Add the argument and mirror to both mutations**

In both `app/graphql/mutations/create_plant.rb` and
`app/graphql/mutations/update_plant.rb`, add the argument:

```ruby
    argument :family_id, GraphQL::Types::ID,
             required: false,
             loads: Types::FamilyType,
             description: 'The botanical family this plant belongs to'
```

`loads:` turns the argument into a `family:` key holding the record, so in each
`resolve`, before saving, apply:

```ruby
      # The legacy free-text column stays authoritative for whatever a human
      # typed. We only fill it in when it is empty, so a plant classified
      # through the new relation still shows something useful in the clients
      # that read family_names, without ever clobbering a person's own words.
      if attributes.key?(:family)
        plant.family = attributes[:family]
        plant.family_names = attributes[:family]&.name if plant.family_names.blank?
      end
```

Remove `:family` from the attribute hash before it is passed to
`assign_attributes`, in the same way the mutations already handle other
`loads:`-backed arguments.

- [ ] **Step 4: Run the spec, then the whole mutation and contract suites**

Run:
```bash
docker compose run --rm -e RAILS_ENV=test web bundle exec rspec \
  spec/mutations/ spec/contracts/
```
Expected: PASS. The mobile write contract must be untouched and green.

- [ ] **Step 5: Regenerate the schema and commit**

```bash
docker compose run --rm -e RAILS_ENV=test web bundle exec rails graphql:schema:dump
git add app/graphql/mutations/create_plant.rb app/graphql/mutations/update_plant.rb \
        schema.graphql spec/mutations/plant_family_assignment_spec.rb
git commit -m "feat(families): set a plant family, mirroring into familyNames only when blank"
```

---

### Task 9: Catalogue of Life client and the seed task

**Files:**
- Create: `lib/catalogue_of_life.rb`
- Create: `lib/tasks/families.rake`
- Test: `spec/lib/catalogue_of_life_spec.rb`

**Interfaces:**
- Consumes: `Family` from Task 1.
- Produces: `CatalogueOfLife.new(dataset: '315834').families(kingdom: 'P')` returning an array of hashes with keys `:name, :col_id, :kingdom, :plant_type`; `CatalogueOfLife::PLANT_TYPE_BY_GROUP`; rake task `families:seed`.

- [ ] **Step 1: Write the failing client spec**

```ruby
# spec/lib/catalogue_of_life_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CatalogueOfLife do
  describe '.plant_type_for' do
    it 'maps every COL group the API returns' do
      {
        'angiosperms' => 'Angiosperms',
        'gymnosperms' => 'Gymnosperms',
        'pteridophytes' => 'Ferns & Fern Allies',
        'bryophytes' => 'Mosses, Liverworts & Hornworts',
        'algae' => 'Algae & Seaweed',
        'protists' => 'Protists',
        'ascomycetes' => 'Fungi',
        'basidiomycetes' => 'Fungi',
        'otherfungi' => 'Fungi',
        'fungi' => 'Fungi',
        'pseudofungi' => 'Fungi',
        'plants' => 'Other Plants',
        'eukaryotes' => 'Other'
      }.each do |group, expected|
        expect(described_class.plant_type_for(group)).to eq(expected)
      end
    end

    it 'returns nil for an unknown group rather than guessing' do
      expect(described_class.plant_type_for('cryptids')).to be_nil
    end
  end

  describe '#families' do
    subject(:client) { described_class.new(dataset: '315834') }

    let(:page) do
      {
        'total' => 1,
        'result' => [{
          'usage' => { 'id' => '623QT', 'name' => { 'scientificName' => 'Fabaceae' } },
          'group' => 'angiosperms'
        }]
      }
    end

    before { allow(client).to receive(:get_page).and_return(page) }

    it 'returns normalised rows' do
      rows = client.families(kingdom_id: 'P', kingdom_name: 'Plantae')
      expect(rows).to eq([{ name: 'Fabaceae', col_id: '623QT',
                            kingdom: 'Plantae', plant_type: 'Angiosperms' }])
    end
  end
end
```

- [ ] **Step 2: Run and confirm failure**

Run: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/lib/catalogue_of_life_spec.rb`
Expected: FAIL, `uninitialized constant CatalogueOfLife`.

- [ ] **Step 3: Write the client**

```ruby
# lib/catalogue_of_life.rb
# frozen_string_literal: true

require 'net/http'
require 'json'

# Reads accepted family-rank taxa from a Catalogue of Life release hosted on
# ChecklistBank.
#
# The pinned release is COL26.7 XR, ChecklistBank dataset 315834, issued
# 2026-07-17. GBIF migrated its own taxonomy to COL Extended Release after the
# GBIF Backbone was frozen at its 2023-08-28 build, which is why we source from
# here rather than GBIF.
class CatalogueOfLife
  HOST = 'https://api.checklistbank.org'
  # ChecklistBank refuses requests without a browser-like agent.
  USER_AGENT = 'Mozilla/5.0 (compatible; echo-plant-api/1.0; +https://echocommunity.org)'
  PAGE_SIZE = 1000
  DEFAULT_DATASET = '315834'
  DEFAULT_VERSION = 'COL26.7 XR'
  DEFAULT_SNAPSHOT = Date.new(2026, 7, 17)

  KINGDOMS = { 'P' => 'Plantae', 'F' => 'Fungi', 'C' => 'Chromista' }.freeze

  # COL publishes its own high-level grouping, which is more reliable than
  # deriving one from phylum and class: an attempt at that misfiled all 78
  # monocot families, because COL splits Magnoliopsida from Liliopsida while
  # both are angiosperms. Verified to cover 100 percent of the 4,596 families.
  PLANT_TYPE_BY_GROUP = {
    'angiosperms' => 'Angiosperms',
    'gymnosperms' => 'Gymnosperms',
    'pteridophytes' => 'Ferns & Fern Allies',
    'bryophytes' => 'Mosses, Liverworts & Hornworts',
    'algae' => 'Algae & Seaweed',
    'protists' => 'Protists',
    'ascomycetes' => 'Fungi',
    'basidiomycetes' => 'Fungi',
    'otherfungi' => 'Fungi',
    'fungi' => 'Fungi',
    'pseudofungi' => 'Fungi',
    'plants' => 'Other Plants',
    'eukaryotes' => 'Other'
  }.freeze

  def self.plant_type_for(group)
    PLANT_TYPE_BY_GROUP[group]
  end

  attr_reader :dataset

  def initialize(dataset: DEFAULT_DATASET)
    @dataset = dataset
  end

  def all_families
    KINGDOMS.flat_map { |id, name| families(kingdom_id: id, kingdom_name: name) }
  end

  def families(kingdom_id:, kingdom_name:)
    rows = []
    offset = 0
    loop do
      page = get_page(kingdom_id, offset)
      results = page['result'] || []
      break if results.empty?

      results.each do |record|
        usage = record['usage'] || {}
        name = usage.dig('name', 'scientificName')
        next if name.blank?

        rows << {
          name: name,
          col_id: usage['id'],
          kingdom: kingdom_name,
          plant_type: self.class.plant_type_for(record['group'])
        }
      end

      offset += PAGE_SIZE
      break if offset >= page['total'].to_i
    end
    rows
  end

  private

  def get_page(kingdom_id, offset)
    uri = URI("#{HOST}/dataset/#{dataset}/nameusage/search")
    uri.query = URI.encode_www_form(
      rank: 'family', status: 'accepted', TAXON_ID: kingdom_id,
      limit: PAGE_SIZE, offset: offset
    )
    JSON.parse(http_get(uri))
  end

  def http_get(uri)
    attempts = 0
    begin
      attempts += 1
      request = Net::HTTP::Get.new(uri, 'User-Agent' => USER_AGENT)
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 90) do |http|
        http.request(request)
      end
      raise "COL responded #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response.body
    rescue StandardError
      # COL publishes no rate limit, so back off rather than hammer it.
      raise if attempts >= 3

      sleep(2**attempts)
      retry
    end
  end
end
```

- [ ] **Step 4: Write the seed rake task**

```ruby
# lib/tasks/families.rake
# frozen_string_literal: true

namespace :families do
  desc <<~DESC
    Seed the locked family list from the Catalogue of Life.
    ENV:
      DRY_RUN  '1' (default) reports without writing, '0' writes
      DATASET  ChecklistBank dataset key (default 315834, COL26.7 XR)
  DESC
  task seed: :environment do
    dry_run = ENV.fetch('DRY_RUN', '1') != '0'
    client = CatalogueOfLife.new(dataset: ENV.fetch('DATASET', CatalogueOfLife::DEFAULT_DATASET))

    puts "Fetching accepted families from Catalogue of Life dataset #{client.dataset}..."
    rows = client.all_families
    puts "Fetched #{rows.size} families."

    unmapped = rows.count { |r| r[:plant_type].nil? }
    puts "WARNING: #{unmapped} families have no plant type mapping." if unmapped.positive?

    by_kingdom = rows.group_by { |r| r[:kingdom] }.transform_values(&:size)
    by_kingdom.each { |k, n| puts format('  %-10s %5d', k, n) }

    existing = Family.pluck(:name).map(&:downcase).to_set
    new_rows = rows.reject { |r| existing.include?(r[:name].downcase) }
    puts "\n#{new_rows.size} new, #{rows.size - new_rows.size} already present."

    if dry_run
      puts "\nDRY RUN. Re-run with DRY_RUN=0 to write."
      next
    end

    now = Time.current
    attributes = rows.map do |row|
      row.merge(
        status: 'accepted',
        classification_source: 'catalogue-of-life',
        classification_version: ENV.fetch('VERSION', CatalogueOfLife::DEFAULT_VERSION),
        snapshot_date: CatalogueOfLife::DEFAULT_SNAPSHOT,
        translations: {},
        created_at: now,
        updated_at: now
      )
    end

    # upsert_all rather than the one-row-at-a-time style used by db/seeds.rb:
    # 4,596 rows through ActiveRecord with Mobility callbacks is needlessly
    # slow, and upserting is what makes a re-run idempotent.
    Family.importing do
      attributes.each_slice(500) do |slice|
        Family.upsert_all(slice, unique_by: 'index_families_on_lower_name',
                                 update_only: %i[col_id kingdom plant_type
                                                 classification_version snapshot_date])
      end
    end

    puts "Done. #{Family.count} families in the table."
    puts "\nData source: Catalogue of Life, CC-BY 4.0."
    puts 'Banki, O., Roskov, Y., Doring, M., Ower, G., et al. (2026). Catalogue of Life.'
  end
end
```

- [ ] **Step 5: Run the client spec, then a real dry run**

Run:
```bash
docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/lib/catalogue_of_life_spec.rb
docker compose run --rm web bundle exec rake families:seed
```
Expected: spec PASS; the dry run reports Plantae 1375, Fungi 1309, Chromista 1912, total 4596, and 0 unmapped plant types.

- [ ] **Step 6: Seed for real in development and verify**

Run:
```bash
docker compose run --rm -e DRY_RUN=0 web bundle exec rake families:seed
docker compose run --rm web bundle exec rails runner 'puts Family.count; puts Family.group(:plant_type).count'
```
Expected: 4596 rows; the plant type histogram matches the design document.

- [ ] **Step 7: Commit**

```bash
git add lib/catalogue_of_life.rb lib/tasks/families.rake spec/lib/catalogue_of_life_spec.rb
git commit -m "feat(families): Catalogue of Life client and idempotent seed task"
```

---

### Task 10: Reconciling the existing plants

**Files:**
- Create: `lib/family_name_normalizer.rb`
- Create: `lib/family_resolver.rb`
- Modify: `lib/tasks/families.rake` (add `reconcile`)
- Test: `spec/lib/family_name_normalizer_spec.rb`, `spec/lib/family_resolver_spec.rb`

**Interfaces:**
- Consumes: `Family`, `CatalogueOfLife`.
- Produces: `FamilyNameNormalizer.call(raw) => { candidates: [String], kind: Symbol }`; `FamilyResolver.new.resolve(name) => { family:, via:, confidence: }`; rake task `families:reconcile`.

- [ ] **Step 1: Write the failing normalizer spec**

Every case below is a real production value.

```ruby
# spec/lib/family_name_normalizer_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FamilyNameNormalizer do
  def candidates(raw)
    described_class.call(raw)[:candidates]
  end

  it 'passes a clean name through' do
    expect(candidates('Fabaceae')).to eq(['Fabaceae'])
  end

  it 'treats a blank value as having no candidates' do
    expect(described_class.call(nil)[:kind]).to eq(:blank)
    expect(described_class.call('   ')[:kind]).to eq(:blank)
  end

  it 'strips leading and trailing whitespace' do
    expect(candidates(' Lauraceae')).to eq(['Lauraceae'])
    expect(candidates('Arecaceae ')).to eq(['Arecaceae'])
  end

  it 'strips a trailing tab' do
    expect(candidates("Musaceae\t")).to eq(['Musaceae'])
  end

  # Production uses EN DASH (U+2013) for this, never an ASCII hyphen.
  it 'drops a common name appended after an en dash' do
    expect(candidates("Cucurbitaceae – Gourd")).to eq(['Cucurbitaceae'])
    expect(candidates("Solanaceae – Nightshade")).to eq(['Solanaceae'])
  end

  it 'drops a common name appended after a run of spaces' do
    expect(candidates('Poaceae   Grass')).to eq(['Poaceae'])
    expect(candidates('Apiaceae   Celery')).to eq(['Apiaceae'])
  end

  it 'drops a common name appended after a single space' do
    expect(candidates('Malvaceae Mallow')).to eq(['Malvaceae'])
  end

  it 'splits a parenthetical alternative into both names' do
    expect(candidates('Asteraceae (Compositae)')).to eq(%w[Asteraceae Compositae])
  end

  it 'splits on the word Or' do
    expect(candidates('Fabaceae Or Leguminosae')).to eq(%w[Fabaceae Leguminosae])
  end

  it 'splits on a comma' do
    expect(candidates('Fabaceae, Legumininosae')).to eq(%w[Fabaceae Legumininosae])
  end

  it 'splits a multi-family string' do
    expect(candidates('Malvaceae  Bombacaceae   Durionaceae'))
      .to eq(%w[Malvaceae Bombacaceae Durionaceae])
  end

  it 'drops a Spanish label appended after an en dash' do
    expect(candidates("Cucurbitaceae – Familia de las Calabazas ")).to eq(['Cucurbitaceae'])
  end

  it 'keeps an unrecognisable value intact for fuzzy matching' do
    expect(candidates('Fabacaea')).to eq(['Fabacaea'])
    expect(described_class.call('Fabacaea')[:kind]).to eq(:unrecognised)
  end
end
```

- [ ] **Step 2: Run and confirm failure**

Run: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/lib/family_name_normalizer_spec.rb`
Expected: FAIL, `uninitialized constant FamilyNameNormalizer`.

- [ ] **Step 3: Write the normalizer**

```ruby
# lib/family_name_normalizer.rb
# frozen_string_literal: true

# Reduces a free-text plants.family_names value to bare family-name candidates.
#
# Neither COL nor GBIF tolerates trailing text: "Cucurbitaceae - Gourd" matches
# nothing at either source, so the cleaning has to happen before any lookup.
# Every transformation here exists because of a value actually present in
# production data.
module FamilyNameNormalizer
  # Family rank names end in -aceae under the modern code. The eight ICN
  # Art. 18.5 conserved alternatives end in -ae instead and are equally valid.
  FAMILY_TOKEN = /\A[A-Z][a-z]+(?:aceae|ae)\z/
  # Production uses EN DASH exclusively for appended labels; ASCII hyphen and
  # em dash are included for safety.
  TRAILING_SEPARATOR = /\s*[–—-]\s*/
  MULTI_SPACE = /\s{2,}/
  JOINERS = /,|\bOr\b|\bor\b|\band\b/

  module_function

  def call(raw)
    return { candidates: [], kind: :blank } if raw.blank?

    value = squish_control_characters(raw)
    return { candidates: [], kind: :blank } if value.blank?

    tokens = split_tokens(value)
    families = tokens.select { |t| t.match?(FAMILY_TOKEN) }
    others = tokens.reject { |t| t.match?(FAMILY_TOKEN) }

    # A single space can also separate a family from an appended common name
    # ("Malvaceae Mallow"), so drop to word level only when nothing else matched.
    if families.empty?
      others.each do |token|
        families.concat(token.split(' ').select { |w| w.match?(FAMILY_TOKEN) })
      end
    end

    families = families.uniq
    return { candidates: [value], kind: :unrecognised } if families.empty?
    return { candidates: families, kind: :multiple_candidates } if families.size > 1

    kind = others.empty? ? :single : :single_with_trailing_text
    { candidates: families, kind: kind }
  end

  def squish_control_characters(raw)
    raw.to_s.tr("\t\r\n", '   ').strip
  end

  def split_tokens(value)
    value
      .split(/[()]/)
      .flat_map { |part| part.split(JOINERS) }
      .flat_map { |part| part.split(TRAILING_SEPARATOR) }
      .flat_map { |part| part.split(MULTI_SPACE) }
      .map(&:strip)
      .reject(&:blank?)
  end
end
```

- [ ] **Step 4: Run the normalizer spec**

Run: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/lib/family_name_normalizer_spec.rb`
Expected: PASS.

- [ ] **Step 5: Write the failing resolver spec**

```ruby
# spec/lib/family_resolver_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FamilyResolver do
  subject(:resolver) { described_class.new }

  before do
    Family.importing do
      create(:family, name: 'Fabaceae')
      create(:family, name: 'Cucurbitaceae')
    end
  end

  it 'resolves a name already in the local list without any network call' do
    expect(resolver).not_to receive(:gbif_spelling)
    result = resolver.resolve('Fabaceae')
    expect(result[:family].name).to eq('Fabaceae')
    expect(result[:via]).to eq(:local)
  end

  it 'uses a GBIF spelling correction and re-resolves locally' do
    allow(resolver).to receive(:gbif_spelling)
      .with('Curcurbitaceae')
      .and_return({ spelling: 'Cucurbitaceae', confidence: 5 })

    result = resolver.resolve('Curcurbitaceae')
    expect(result[:family].name).to eq('Cucurbitaceae')
    expect(result[:via]).to eq(:gbif_corrected)
    expect(result[:confidence]).to eq(5)
  end

  it 'returns no family when nothing resolves' do
    allow(resolver).to receive(:gbif_spelling).and_return(nil)
    expect(resolver.resolve('Leguminaceae')[:family]).to be_nil
  end

  # Without a kingdom and rank guard, GBIF answers this typo with Hiatellidae,
  # a bivalve mollusc family, at confidence 0.
  it 'refuses an out-of-scope kingdom suggestion' do
    expect(resolver.send(:acceptable_gbif_match?,
                         { 'family' => 'Hiatellidae', 'kingdom' => 'Animalia',
                           'matchType' => 'FUZZY' })).to be false
    expect(resolver.send(:acceptable_gbif_match?,
                         { 'family' => 'Rosaceae', 'kingdom' => 'Plantae',
                           'matchType' => 'FUZZY' })).to be true
  end
end
```

- [ ] **Step 6: Write the resolver**

```ruby
# lib/family_resolver.rb
# frozen_string_literal: true

require 'net/http'
require 'json'

# Resolves a cleaned family-name candidate to a Family row.
#
# The local list is authoritative, because it came from the Catalogue of Life,
# which gets family merges right where GBIF does not: COL treats Tiliaceae,
# Durionaceae, Asclepiadaceae, Chenopodiaceae and Bombacaceae as synonyms of
# their modern families, and routes Guttiferae to Clusiaceae as the botanical
# code requires, where GBIF sends it to Hypericaceae.
#
# COL has no fuzzy matching at all, so genuine typos need GBIF. GBIF is asked
# only how a name should be SPELLED; the corrected spelling is then resolved
# against the local COL-sourced list, so COL always decides which family a
# plant belongs to.
class FamilyResolver
  GBIF_MATCH = 'https://api.gbif.org/v1/species/match'
  IN_SCOPE_KINGDOMS = %w[Plantae Fungi Chromista].freeze

  def resolve(name)
    local = find_local(name)
    return { family: local, via: :local, confidence: nil } if local

    corrected = gbif_spelling(name)
    if corrected
      family = find_local(corrected[:spelling])
      if family
        return { family: family, via: :gbif_corrected,
                 confidence: corrected[:confidence], spelling: corrected[:spelling] }
      end
    end

    { family: nil, via: :unresolved, confidence: nil }
  end

  private

  def find_local(name)
    Family.accepted.find_by('lower(name) = ?', name.to_s.downcase)
  end

  # Guard on kingdom and rank, not confidence. A threshold cannot separate the
  # good from the bad here: the correct recovery of Curcurbitaceae comes back at
  # confidence 5, while the garbage match for Fabacaea comes back at 0.
  def acceptable_gbif_match?(payload)
    return false if payload.nil?
    return false if payload['family'].blank?
    return false unless IN_SCOPE_KINGDOMS.include?(payload['kingdom'])

    !['NONE', nil].include?(payload['matchType'])
  end

  def gbif_spelling(name)
    payload = gbif_match(name)
    return nil if payload.nil?

    if acceptable_gbif_match?(payload)
      return { spelling: payload['family'], confidence: payload['confidence'] }
    end

    alternative = (payload['alternatives'] || []).find { |alt| acceptable_gbif_match?(alt) }
    return nil unless alternative

    { spelling: alternative['family'], confidence: alternative['confidence'] }
  end

  def gbif_match(name)
    uri = URI(GBIF_MATCH)
    uri.query = URI.encode_www_form(name: name, rank: 'FAMILY', verbose: 'true')
    response = Net::HTTP.get_response(uri)
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue StandardError
    nil
  end
end
```

- [ ] **Step 7: Add the reconcile task**

Append to `lib/tasks/families.rake`, inside the namespace:

```ruby
  desc <<~DESC
    Reconcile existing plants.family_names onto the families table.
    Writes a reviewable report and, unless DRY_RUN=0, changes nothing.
    ENV:
      DRY_RUN     '1' (default) reports only, '0' applies the confident matches
      MIN_CONFIDENCE  auto-apply floor for a GBIF spelling fix (default 80)
  DESC
  task reconcile: :environment do
    dry_run = ENV.fetch('DRY_RUN', '1') != '0'
    floor = ENV.fetch('MIN_CONFIDENCE', '80').to_i
    resolver = FamilyResolver.new
    cache = {}

    applied = []
    review = []
    blank = []

    Plant.find_each do |plant|
      parsed = FamilyNameNormalizer.call(plant.family_names)
      if parsed[:kind] == :blank
        blank << plant
        next
      end

      results = parsed[:candidates].map { |c| cache[c] ||= resolver.resolve(c) }
      families = results.filter_map { |r| r[:family] }.uniq

      if families.size != 1 || results.any? { |r| r[:family].nil? }
        review << { plant: plant, results: results, reason: :unresolved_or_conflicting }
        next
      end

      confidences = results.filter_map { |r| r[:confidence] }
      if confidences.any? && confidences.min < floor
        review << { plant: plant, results: results, reason: :low_confidence,
                    family: families.first }
        next
      end

      applied << { plant: plant, family: families.first }
    end

    puts '=' * 68
    puts "RECONCILIATION REPORT - #{Plant.count} plants"
    puts '=' * 68
    puts format('  %-46s %5d', 'Would be applied', applied.size)
    puts format('  %-46s %5d', 'Requires a human decision', review.size)
    puts format('  %-46s %5d', 'Blank family_names, left null', blank.size)

    puts "\nEVERY RECORD REQUIRING A HUMAN DECISION"
    review.each do |row|
      puts "\n  plant : #{row[:plant].scientific_name}"
      puts "  raw   : #{row[:plant].family_names.inspect}"
      puts "  reason: #{row[:reason]}"
      row[:results].each do |r|
        puts "          -> #{r[:family]&.name || '(no match)'} via=#{r[:via]} conf=#{r[:confidence]}"
      end
    end

    puts "\nRESULTING FAMILY DISTRIBUTION"
    applied.group_by { |a| a[:family].name }.sort_by { |_, v| -v.size }.each do |name, rows|
      puts format('  %4d  %s', rows.size, name)
    end

    if dry_run
      puts "\nDRY RUN. Nothing was written. Re-run with DRY_RUN=0 to apply."
      next
    end

    applied.each { |row| row[:plant].update_columns(family_id: row[:family].id) }
    puts "\nApplied #{applied.size} family links. #{review.size} still need review."
  end
```

`update_columns` is deliberate: reconciliation is a data repair, and it must not
touch `updated_at`, fire PaperTrail versions for every row, or run the
blank-mirror logic.

- [ ] **Step 8: Run both specs and a dry run**

Run:
```bash
docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/lib/
docker compose run --rm web bundle exec rake families:reconcile
```
Expected: specs PASS. Against a production-shaped dataset the report should show
292 applied, 8 for review and 22 blank.

- [ ] **Step 9: Commit**

```bash
git add lib/family_name_normalizer.rb lib/family_resolver.rb lib/tasks/families.rake \
        spec/lib/family_name_normalizer_spec.rb spec/lib/family_resolver_spec.rb
git commit -m "feat(families): reconcile existing free-text family names with a review report"
```

---

### Task 11: Load the issue #83 seed-banking metadata

**Files:**
- Create: `db/seeds/family_seed_banking.csv`
- Modify: `lib/tasks/families.rake` (add `load_seed_banking`)
- Test: `spec/tasks/family_seed_banking_spec.rb`

**Interfaces:**
- Consumes: `Family` from Task 1.
- Produces: rake task `families:load_seed_banking`; populated `storage_physiology`, `seed_longevity`, `seed_banking_rank` and translated `seed_banking_notes`.

**The CSV already exists** at `db/seeds/family_seed_banking.csv`, generated from
the second spreadsheet attached to issue #83. It has 347 data rows and the header
`family,storage_physiology,seed_longevity,seed_banking_rank,seed_banking_notes`.

Values are carried across **verbatim**; normalisation happens in the loader, not
in the file, so the file stays a faithful record of what was supplied. That means
87 of its lines contain a literal en dash in the `seed_longevity` column, which
is exactly the input `normalize_longevity` has to merge with the ASCII-hyphen
spelling. Do not "fix" the CSV; fix it in code, and let the spec prove it.

`Seed Size & Handling` and `Dormancy & Germination` are absent by design.

- [ ] **Step 1: Write the failing loader spec**

```ruby
# spec/tasks/family_seed_banking_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FamilySeedBankingLoader do
  before do
    Family.importing do
      create(:family, name: 'Amaranthaceae')
      create(:family, name: 'Malvaceae')
    end
  end

  describe '.normalize_longevity' do
    # The source file splits one value across an en dash and a hyphen.
    it 'merges the two dash spellings of Low-Medium' do
      expect(described_class.normalize_longevity("Low–Medium")).to eq('low_medium')
      expect(described_class.normalize_longevity('Low-Medium')).to eq('low_medium')
    end

    it 'maps the simple values' do
      expect(described_class.normalize_longevity('High')).to eq('high')
      expect(described_class.normalize_longevity("Medium–High")).to eq('medium_high')
    end

    it 'returns nil for a blank' do
      expect(described_class.normalize_longevity('')).to be_nil
    end
  end

  describe '.normalize_storage' do
    it 'maps the four dominant values' do
      expect(described_class.normalize_storage('Orthodox')).to eq('orthodox')
      expect(described_class.normalize_storage('Recalcitrant')).to eq('recalcitrant')
      expect(described_class.normalize_storage('Variable')).to eq('variable')
      expect(described_class.normalize_storage('Mixed')).to eq('mixed')
    end

    it 'maps hedged variants to their category' do
      expect(described_class.normalize_storage('Mostly orthodox')).to eq('orthodox')
      expect(described_class.normalize_storage('Likely recalcitrant')).to eq('recalcitrant')
      expect(described_class.normalize_storage('Recalcitrant/intermediate')).to eq('intermediate')
    end

    it 'maps limited data to unknown' do
      expect(described_class.normalize_storage('Limited data')).to eq('unknown')
    end
  end

  describe '.qualifier_from' do
    # "Mostly orthodox (onions, garlic, leeks)" loses real editorial content if
    # only the enum is kept, so the parenthetical is preserved in the notes.
    it 'extracts a parenthetical qualifier' do
      expect(described_class.qualifier_from('Mostly orthodox (onions, garlic, leeks)'))
        .to eq('onions, garlic, leeks')
    end

    it 'returns nil when there is none' do
      expect(described_class.qualifier_from('Orthodox')).to be_nil
    end
  end

  describe '.call' do
    let(:rows) do
      [{ 'family' => 'Amaranthaceae', 'storage_physiology' => 'Orthodox',
         'seed_longevity' => 'High', 'seed_banking_rank' => '5',
         'seed_banking_notes' => 'Highly suitable' },
       # A family COL treats as a synonym: its metadata must land on the
       # accepted family instead of being dropped.
       { 'family' => 'Chenopodiaceae', 'storage_physiology' => 'Orthodox',
         'seed_longevity' => 'Medium', 'seed_banking_rank' => '4',
         'seed_banking_notes' => 'Merged family' },
       { 'family' => 'Pomaceae', 'storage_physiology' => 'Orthodox',
         'seed_longevity' => 'High', 'seed_banking_rank' => '5',
         'seed_banking_notes' => 'No COL target' }]
    end

    it 'loads metadata onto a matching family' do
      described_class.call(rows, redirects: {}, dry_run: false)
      family = Family.find_by(name: 'Amaranthaceae')
      expect(family.storage_physiology).to eq('orthodox')
      expect(family.seed_longevity).to eq('high')
      expect(family.seed_banking_rank).to eq(5)
      expect(family.seed_banking_notes).to eq('Highly suitable')
    end

    it 'redirects a synonym onto its accepted family' do
      described_class.call(rows, redirects: { 'Chenopodiaceae' => 'Amaranthaceae' },
                                 dry_run: false)
      expect(Family.find_by(name: 'Amaranthaceae').seed_banking_rank).to eq(4)
    end

    it 'reports rather than guesses when there is no target' do
      report = described_class.call(rows, redirects: {}, dry_run: false)
      expect(report[:unmatched]).to include('Pomaceae')
    end

    it 'writes nothing on a dry run' do
      described_class.call(rows, redirects: {}, dry_run: true)
      expect(Family.find_by(name: 'Amaranthaceae').seed_banking_rank).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run and confirm failure**

Run: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/tasks/family_seed_banking_spec.rb`
Expected: FAIL, `uninitialized constant FamilySeedBankingLoader`.

- [ ] **Step 3: Write the loader**

```ruby
# lib/family_seed_banking_loader.rb
# frozen_string_literal: true

# Loads the family-level seed banking guidance supplied on issue #83.
#
# Only four of the spreadsheet's six columns are loaded. "Seed Size & Handling"
# and "Dormancy & Germination" are a single value for 303 of 347 rows
# ("Variable" and "Varies by species"), so they carry almost no information and
# are left out until they have real content.
#
# The "Count" column from the companion spreadsheet is deliberately NOT stored:
# it is a count of Food Plants International records per family, so it would be
# stale on write and excludes ECHO's own plants. Family.plants totalCount serves
# that need and is always correct.
module FamilySeedBankingLoader
  LONGEVITY = {
    'low' => 'low',
    'low-medium' => 'low_medium',
    'medium' => 'medium',
    'medium-high' => 'medium_high',
    'high' => 'high'
  }.freeze

  module_function

  # The source splits one value across an en dash and an ASCII hyphen:
  # 86 rows say "Low-Medium" with U+2013 and 23 say it with '-'.
  def normalize_longevity(value)
    return nil if value.blank?

    key = value.to_s.strip.downcase.tr("–—", '--')
    LONGEVITY[key]
  end

  def normalize_storage(value)
    return nil if value.blank?

    text = value.to_s.downcase
    return 'unknown' if text.include?('limited data')
    return 'intermediate' if text.include?('intermediate')
    return 'mixed' if text.start_with?('mixed')
    return 'variable' if text.start_with?('variable')
    return 'recalcitrant' if text.include?('recalcitrant')
    return 'orthodox' if text.include?('orthodox')

    'unknown'
  end

  # "Mostly orthodox (onions, garlic, leeks)" carries editorial detail that the
  # enum cannot hold. Keep it rather than silently discarding it.
  def qualifier_from(value)
    match = value.to_s.match(/\(([^)]+)\)/)
    match && match[1]
  end

  def call(rows, redirects: {}, dry_run: true)
    report = { updated: [], unmatched: [], redirected: [] }

    rows.each do |row|
      source_name = row['family'].to_s.strip
      target_name = redirects.fetch(source_name, source_name)
      family = Family.accepted.find_by('lower(name) = ?', target_name.downcase)

      if family.nil?
        report[:unmatched] << source_name
        next
      end

      report[:redirected] << [source_name, target_name] if target_name != source_name

      notes = row['seed_banking_notes'].to_s.strip
      qualifier = qualifier_from(row['storage_physiology'])
      notes = [notes, qualifier && "Storage detail: #{qualifier}"].compact.join('. ')

      next if dry_run

      family.storage_physiology = normalize_storage(row['storage_physiology'])
      family.seed_longevity = normalize_longevity(row['seed_longevity'])
      family.seed_banking_rank = row['seed_banking_rank'].presence&.to_i
      Mobility.with_locale(:en) { family.seed_banking_notes = notes.presence }
      family.save!
      report[:updated] << family.name
    end

    report
  end
end
```

- [ ] **Step 4: Add the rake task**

Append to `lib/tasks/families.rake`:

```ruby
  desc <<~DESC
    Load the family seed banking metadata from issue #83.
    ENV:
      DRY_RUN '1' (default) reports only, '0' writes
      FILE    CSV path (default db/seeds/family_seed_banking.csv)
  DESC
  task load_seed_banking: :environment do
    require 'csv'

    path = ENV.fetch('FILE', 'db/seeds/family_seed_banking.csv')
    rows = CSV.read(path, headers: true).map(&:to_h)

    # Six of Steve's families are synonyms in COL, so their guidance belongs on
    # the accepted family. Pomaceae and Lycoperdiaceae have no COL target at all
    # and are reported rather than guessed at.
    redirects = {
      'Chenopodiaceae' => 'Amaranthaceae',
      'Cystoseiraceae' => 'Sargassaceae',
      'Exidiaceae' => 'Auriculariaceae',
      'Melanogastraceae' => 'Paxillaceae',
      'Nostochopsidaceae' => 'Hapalosiphonaceae',
      'Leuconostocaceae' => 'Lactobacillaceae'
    }

    report = FamilySeedBankingLoader.call(
      rows, redirects: redirects, dry_run: ENV.fetch('DRY_RUN', '1') != '0'
    )

    puts "rows in file        : #{rows.size}"
    puts "updated             : #{report[:updated].size}"
    puts "redirected to accepted family:"
    report[:redirected].uniq.each { |from, to| puts "  #{from} -> #{to}" }
    puts "NO TARGET, needs a decision (#{report[:unmatched].size}):"
    report[:unmatched].each { |name| puts "  #{name}" }
  end
```

- [ ] **Step 5: Run the spec, then a dry run**

Run:
```bash
docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/tasks/family_seed_banking_spec.rb
docker compose run --rm web bundle exec rake families:load_seed_banking
```
Expected: spec PASS; the dry run reports 347 rows, 6 redirects, and exactly
`Pomaceae` and `Lycoperdiaceae` as needing a decision.

- [ ] **Step 6: Commit**

```bash
git add lib/family_seed_banking_loader.rb lib/tasks/families.rake \
        db/seeds/family_seed_banking.csv spec/tasks/family_seed_banking_spec.rb
git commit -m "feat(families): load seed banking metadata from issue #83"
```

---

### Task 12: The refresh task

**Files:**
- Modify: `lib/tasks/families.rake` (add `refresh`)
- Create: `lib/family_refresh.rb`
- Test: `spec/lib/family_refresh_spec.rb`

**Interfaces:**
- Consumes: `CatalogueOfLife`, `Family`.
- Produces: `FamilyRefresh.new(rows).diff => { added:, renamed:, merged:, split:, vanished: }`; rake task `families:refresh`.

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/lib/family_refresh_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FamilyRefresh do
  before do
    Family.importing do
      create(:family, name: 'Malvaceae', col_id: 'CDB')
      create(:family, name: 'Tiliaceae', col_id: 'H9G')
    end
  end

  def upstream(*names)
    names.map { |n| { name: n, col_id: "X#{n}", kingdom: 'Plantae', plant_type: 'Angiosperms' } }
  end

  it 'reports a family that is new upstream' do
    diff = described_class.new(upstream('Malvaceae', 'Tiliaceae', 'Brassicaceae')).diff
    expect(diff[:added].map { |r| r[:name] }).to eq(['Brassicaceae'])
  end

  it 'reports a family that has vanished upstream' do
    diff = described_class.new(upstream('Malvaceae')).diff
    expect(diff[:vanished].map(&:name)).to eq(['Tiliaceae'])
  end

  it 'counts the plants affected by a vanished family' do
    tiliaceae = Family.find_by(name: 'Tiliaceae')
    create(:plant, family: tiliaceae)
    diff = described_class.new(upstream('Malvaceae')).diff
    expect(diff[:affected_plant_counts]['Tiliaceae']).to eq(1)
  end

  it 'applies nothing during a diff' do
    described_class.new(upstream('Malvaceae')).diff
    expect(Family.find_by(name: 'Tiliaceae')).to be_present
    expect(Family.find_by(name: 'Tiliaceae').status).to eq('accepted')
  end

  describe '#apply_merge' do
    it 'repoints plants and supersedes the old family' do
      tiliaceae = Family.find_by(name: 'Tiliaceae')
      malvaceae = Family.find_by(name: 'Malvaceae')
      plant = create(:plant, family: tiliaceae)

      described_class.new([]).apply_merge(tiliaceae, malvaceae)

      expect(plant.reload.family).to eq(malvaceae)
      expect(tiliaceae.reload.status).to eq('superseded')
      expect(tiliaceae.superseded_by).to eq(malvaceae)
    end

    it 'keeps the superseded row so nothing dangles' do
      tiliaceae = Family.find_by(name: 'Tiliaceae')
      described_class.new([]).apply_merge(tiliaceae, Family.find_by(name: 'Malvaceae'))
      expect(Family.find_by(name: 'Tiliaceae')).to be_present
    end
  end
end
```

- [ ] **Step 2: Run and confirm failure**

Run: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/lib/family_refresh_spec.rb`
Expected: FAIL, `uninitialized constant FamilyRefresh`.

- [ ] **Step 3: Write the refresh logic**

```ruby
# lib/family_refresh.rb
# frozen_string_literal: true

# Diffs the locked family list against a Catalogue of Life release.
#
# The governing rule is that a refresh NEVER silently repoints a plant. It
# reports what changed; a human confirms; only then is anything applied.
#
# Matching is by NAME, not by COL identifier. COL identifiers are forced to
# change whenever a name flips between accepted and synonym, which is exactly
# what a merge is, so keying on them would make merges undetectable and would
# orphan our rows. Family names are stable; their status is what moves.
class FamilyRefresh
  def initialize(upstream_rows)
    @upstream = upstream_rows
    @upstream_by_name = upstream_rows.index_by { |r| r[:name].downcase }
  end

  def diff
    local = Family.accepted.to_a
    local_names = local.map { |f| f.name.downcase }.to_set

    added = @upstream.reject { |r| local_names.include?(r[:name].downcase) }
    vanished = local.reject { |f| @upstream_by_name.key?(f.name.downcase) }

    {
      added: added,
      vanished: vanished,
      affected_plant_counts: vanished.to_h { |f| [f.name, f.plants.count] },
      unchanged: local.size - vanished.size
    }
  end

  # A merge is applied only after a human has confirmed it. Plants move to the
  # accepted family and the old row is kept, marked superseded, so that any
  # reference to it still resolves and the history stays readable.
  def apply_merge(from_family, to_family)
    Family.transaction do
      from_family.plants.update_all(family_id: to_family.id)
      from_family.update!(status: 'superseded', superseded_by: to_family)
    end
  end
end
```

- [ ] **Step 4: Add the rake task**

Append to `lib/tasks/families.rake`:

```ruby
  desc <<~DESC
    Diff the family list against a Catalogue of Life release and report changes.
    Applies nothing without APPLY=1 and an explicit confirmation.
    ENV:
      DATASET  ChecklistBank dataset key to compare against
      APPLY    '1' to apply additions and confirmed merges
  DESC
  task refresh: :environment do
    client = CatalogueOfLife.new(dataset: ENV.fetch('DATASET', CatalogueOfLife::DEFAULT_DATASET))
    puts "Fetching #{client.dataset}..."
    upstream = client.all_families
    diff = FamilyRefresh.new(upstream).diff

    puts '=' * 68
    puts 'FAMILY REFRESH DIFF'
    puts '=' * 68
    puts format('  %-40s %5d', 'unchanged', diff[:unchanged])
    puts format('  %-40s %5d', 'new upstream (would be added)', diff[:added].size)
    puts format('  %-40s %5d', 'gone upstream (needs a decision)', diff[:vanished].size)

    if diff[:vanished].any?
      puts "\nFAMILIES NO LONGER ACCEPTED UPSTREAM"
      puts 'Each needs a human decision. Nothing is repointed automatically.'
      diff[:vanished].each do |family|
        count = diff[:affected_plant_counts][family.name]
        puts "  #{family.name} (#{count} plant(s) reference it)"
      end
    end

    unless ENV['APPLY'] == '1'
      puts "\nREPORT ONLY. Nothing was written. Re-run with APPLY=1 to add new families."
      next
    end

    print "\nAdd #{diff[:added].size} new families? Type 'yes' to continue: "
    unless $stdin.gets.to_s.strip == 'yes'
      puts 'Aborted.'
      next
    end

    now = Time.current
    Family.importing do
      diff[:added].each_slice(500) do |slice|
        Family.upsert_all(
          slice.map do |row|
            row.merge(status: 'accepted', classification_source: 'catalogue-of-life',
                      classification_version: ENV.fetch('VERSION', CatalogueOfLife::DEFAULT_VERSION),
                      snapshot_date: CatalogueOfLife::DEFAULT_SNAPSHOT,
                      translations: {}, created_at: now, updated_at: now)
          end,
          unique_by: 'index_families_on_lower_name'
        )
      end
    end
    puts "Added #{diff[:added].size}. Merges must be applied individually after review."
  end
```

Merges are deliberately not batch-applied: each one needs a human to confirm the
target, which is what `FamilyRefresh#apply_merge` is for.

- [ ] **Step 5: Run the spec**

Run: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/lib/family_refresh_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/family_refresh.rb lib/tasks/families.rake spec/lib/family_refresh_spec.rb
git commit -m "feat(families): refresh task that diffs against COL and never auto-repoints"
```

---

### Task 13: Prove nothing else changed

**Files:**
- Create: `spec/contracts/family_backward_compatibility_spec.rb`
- Modify: `docs/authorization-trust-levels.md`

**Interfaces:**
- Consumes: everything above.
- Produces: evidence that existing queries are byte-identical.

- [ ] **Step 1: Write the byte-identical evidence spec**

```ruby
# spec/contracts/family_backward_compatibility_spec.rb
# frozen_string_literal: true

require 'rails_helper'

# The brief requires demonstrating, not asserting, that existing queries return
# byte-identical results for every field other than the new ones.
RSpec.describe 'families changes nothing that already worked', type: :request do
  let(:family) { Family.importing { create(:family, name: 'Fabaceae') } }

  # Exactly the field set the frozen mobile app requests in getPlantDetail.
  let(:mobile_query) do
    <<~GQL
      query($id: ID!) {
        plant(id: $id) {
          id primaryCommonName description scientificName familyNames
          createdBy createdAt updatedAt ownedBy
        }
      }
    GQL
  end

  def mobile_payload(plant)
    PlantApiSchema.execute(
      mobile_query,
      variables: { 'id' => PlantApiSchema.id_from_object(plant, Plant, {}) },
      context: { current_user: nil }
    ).to_h
  end

  it 'returns an identical payload whether or not a family is linked' do
    plant = create(:plant, :public, family_names: 'Leguminosae', family: nil)
    before = mobile_payload(plant)

    plant.update_columns(family_id: family.id)
    after = mobile_payload(plant.reload)

    expect(after).to eq(before)
  end

  it 'still returns the human-typed familyNames verbatim' do
    plant = create(:plant, :public, family_names: "Cucurbitaceae – Gourd", family: family)
    payload = mobile_payload(plant)
    expect(payload.dig('data', 'plant', 'familyNames')).to eq("Cucurbitaceae – Gourd")
  end

  it 'keeps familyNames nullable and untyped as a plain String' do
    field = PlantApiSchema.types['Plant'].fields['familyNames']
    expect(field.type.to_type_signature).to eq('String')
    expect(field.deprecation_reason).to be_nil
  end
end
```

- [ ] **Step 2: Run it**

Run: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/contracts/`
Expected: PASS, including the pre-existing mobile read and write contracts.

- [ ] **Step 3: Document the trust level exception**

Add to `docs/authorization-trust-levels.md`, under the level table:

```markdown
### Exception: family metadata is editable at 9, not 10

The other lookup tables (Tolerance, GrowthHabit, Antinutrient, ImageAttribute)
require trust level 10 for every write, because their lists are editable and a
lower bar would let anyone fork a shared vocabulary.

The family list cannot be forked: it is locked at the model and in the database,
and no create or delete mutation exists. Only the metadata layered on top is
editable, so that is gated at level 9. Note also that no account currently holds
plant trust 10, so gating family metadata there would make it uneditable by
anyone.
```

- [ ] **Step 4: Run the full suite and the linter**

Run:
```bash
docker compose run --rm -e RAILS_ENV=test web bundle exec rspec
docker compose run --rm web bundle exec rubocop
docker compose run --rm -e RAILS_ENV=test web bundle exec rails graphql:schema:dump
git diff --exit-code schema.graphql
```
Expected: examples >= 1936 with 0 failures; RuboCop 0 offences; no schema drift.

- [ ] **Step 5: Commit**

```bash
git add spec/contracts/family_backward_compatibility_spec.rb \
        docs/authorization-trust-levels.md schema.graphql
git commit -m "test(families): demonstrate existing queries are byte-identical"
```

---

## Deployment sequence

1. Merge to `master`. CI runs rspec, RuboCop and the schema-drift gate.
2. Staging deploys automatically; the migration runs there first.
3. Approve the production deploy at the reviewer gate.
4. On production, in order: `families:seed` dry run, then `DRY_RUN=0`.
5. `families:load_seed_banking` dry run, then `DRY_RUN=0`.
6. `families:reconcile` dry run. **Share the report and get sign-off on the 8
   review cases before applying.** Then `DRY_RUN=0`.
7. Verify: `families` has 4,596 rows; 292 plants have a `family_id`; anonymous
   `plants` still returns 322 with `familyNames` unchanged.

Only then start the SPA plan, which needs the deployed schema for codegen.
