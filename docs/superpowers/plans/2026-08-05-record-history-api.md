# Record History API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose the PaperTrail audit trail for plants and varieties as a `recordHistory` GraphQL connection with server-computed diffs, resolved actors, aggregated child-row entries, and per-type restore-to-a-version mutations.

**Architecture:** Child rows (common names, the seven plant/variety join models, images) stamp `{root_type, root_id}` into `versions.metadata` after PaperTrail writes each version, so one indexed query (`item_type/item_id` OR `metadata @>`) returns a record's whole timeline. Plain Ruby services under `app/services/change_history/` turn a `PaperTrail::Version` row into a presentable change entry (diff, subject, actor) and perform a restore by reifying the version that follows the chosen one. The GraphQL layer is a thin type over `PaperTrail::Version` plus two mutations, gated by the same Pundit `update?` that gates editing.

**Tech Stack:** Rails 8.1.3, Ruby 3.4.10, PostgreSQL (jsonb + GIN), paper_trail 17.0.0, graphql-ruby 2.3.23, Pundit, Mobility (container backend), RSpec + FactoryBot + Faker, RuboCop.

## Global Constraints

- Work dir: `/work/plant_data_upgrade/.worktrees/api-version-history` (branch `version-history`; baseline: 1943 examples, 0 failures). All commands run from that directory.
- Test command: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec <path>` (test DB already prepared; `docker-compose.override.yml` gives this worktree an isolated Postgres volume -- leave it untracked, never `git add` it).
- Lint: `docker compose run --rm web bundle exec rubocop` must pass with zero offenses. `rubocop-rails` is NOT installed: never write a `# rubocop:disable Rails/...` comment (an unknown cop name is itself reported as `Lint/RedundantCopDisableDirective`). Fix offenses by changing the code; do not add `.rubocop_todo.yml` entries.
- ASCII only in every committed file. No em-dashes anywhere (use `--`). No emoji.
- This is a PUBLIC repo: no real emails, uids, or person names in code, specs, fixtures, or commit messages. Factories use Faker/synthetic values only.
- Schema changes are strictly additive. `spec/contracts/mobile_*` must remain untouched and green.
- Any spec that asserts PaperTrail version rows exist MUST be tagged `versioning: true` (the paper_trail rspec hook sets `PaperTrail.enabled = false` for every other example).
- Migrations: `schema_format` is `:sql` (`db/structure.sql`), UUID primary keys on domain tables, `versions.id` is `bigint`, `versions.item_id` is `uuid`, `versions.metadata` is `jsonb`.
- `schema.graphql` is a checked-in artifact and CI runs a drift gate (`rails graphql:schema:dump` then `git diff --exit-code schema.graphql`). Any task that adds or changes a GraphQL type/field MUST regenerate it with `docker compose run --rm -e RAILS_ENV=test web bundle exec rails graphql:schema:dump` and commit the diff.
- Git commits: end every commit message with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`. Use the form:
  `git commit -m "<subject>" -m "<body>" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"`
- Verified PaperTrail 17 fact used throughout (read from `paper_trail-17.0.0/lib/paper_trail/events/base.rb`): `merge_metadata_into(data)` calls `merge_metadata_from_model_into(data)` FIRST (which does `data[k] = ...` for each model `meta:` entry) and THEN returns `data.merge(PaperTrail.request.controller_info || {})`. Controller info therefore REPLACES a model-level `meta:` value for the same key. Since `ApplicationController#info_for_paper_trail` returns `{ metadata: { origin:, principal_id: } }`, a model `meta: { metadata: -> {...} }` lambda would be silently discarded on every API write. Root stamping is therefore done by merging into the version row AFTER PaperTrail writes it (Task 2).
- Existing frozen contract, used by the diff builder: the legacy visibility enum is `{ private: 0, public: 1, draft: 2, deleted: 3 }`.
- Namespace note: PaperTrail 17 defines `PaperTrail::RecordHistory` internally. Our service namespace is therefore `ChangeHistory`, never `RecordHistory`.
- GraphQL SDL naming resolution (deviation from the literal text of the spec): the spec's SDL snippets used Ruby class names (`ChangeEventType`, `FieldChangeType`). The shipped SDL uses house style (a `Types::FooType` class produces SDL name `Foo`): **ChangeEntry, FieldChange, ChangeEvent, ChangeOrigin, ChangeSubject**. All *field* and *argument* names are exactly as the spec: `recordHistory`, `createdAt`, `event`, `origin`, `actor`, `actorLabel`, `subjectType`, `subjectLabel`, `changes { field locale before after }`, `restorable`, `restorePlantVersion(plantId:, versionId:)`, `restoreVarietyVersion(varietyId:, versionId:)`.

---

### Task 1: GIN index on versions.metadata

**Files:**
- Create: `db/migrate/20260805000001_add_gin_index_to_versions_metadata.rb`
- Modify: `db/structure.sql` (regenerated by the migration, do not hand-edit)
- Test: `spec/models/versions_metadata_index_spec.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: Postgres index `index_versions_on_metadata_jsonb_path_ops` (`USING gin (metadata jsonb_path_ops)`), which backs the `metadata @> ...` containment lookup in Task 3.

**Steps:**

- [ ] Write the failing test at `spec/models/versions_metadata_index_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

# The aggregated record history finds child versions with
# `versions.metadata @> '{"root_type":...,"root_id":...}'`. That containment
# operator is only indexable by a GIN index; jsonb_path_ops supports exactly
# the @> operator and is about half the size of the default jsonb_ops.
RSpec.describe 'versions.metadata GIN index', type: :model do
  it 'indexes versions.metadata with a GIN index for containment lookups' do
    index = ActiveRecord::Base.connection.indexes('versions').find do |i|
      i.name == 'index_versions_on_metadata_jsonb_path_ops'
    end

    expect(index).not_to be_nil
    expect(index.using).to eq(:gin)
    expect(index.columns).to eq(['metadata'])
  end
end
```
- [ ] Run `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/models/versions_metadata_index_spec.rb`. Expect 1 failure: `expected: not nil, got: nil` (the index does not exist yet).
- [ ] Create `db/migrate/20260805000001_add_gin_index_to_versions_metadata.rb`:
```ruby
# frozen_string_literal: true

# Aggregated record history looks child versions up with
# `versions.metadata @> '{"root_type":"Plant","root_id":"<uuid>"}'`.
#
# GIN with jsonb_path_ops is the operator class for @> containment: smaller and
# faster than the default jsonb_ops, at the cost of key-existence operators we
# do not use. CONCURRENTLY keeps the build off an ACCESS EXCLUSIVE lock on a
# table every write in the application appends to; it cannot run inside a
# transaction, hence disable_ddl_transaction!.
class AddGinIndexToVersionsMetadata < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :versions,
              :metadata,
              using: :gin,
              opclass: :jsonb_path_ops,
              algorithm: :concurrently,
              name: 'index_versions_on_metadata_jsonb_path_ops',
              if_not_exists: true
  end
end
```
- [ ] Apply it and regenerate `db/structure.sql`: `docker compose run --rm -e RAILS_ENV=test web bundle exec rails db:migrate`. (If that reports the database does not exist, run `docker compose run --rm -e RAILS_ENV=test web bundle exec rails db:create db:migrate`.) Expect `db/structure.sql` to gain a `CREATE INDEX index_versions_on_metadata_jsonb_path_ops ON public.versions USING gin (metadata jsonb_path_ops);` line and a new `('20260805000001')` entry in the schema_migrations insert list.
- [ ] Re-run `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/models/versions_metadata_index_spec.rb`. Expect `1 example, 0 failures`.
- [ ] Run `docker compose run --rm web bundle exec rubocop`. Expect `no offenses detected`.
- [ ] Commit:
```bash
git add db/migrate/20260805000001_add_gin_index_to_versions_metadata.rb db/structure.sql spec/models/versions_metadata_index_spec.rb
git commit -m "Add GIN index on versions.metadata for record history" -m "Aggregated history matches child versions with a jsonb containment lookup. jsonb_path_ops is the operator class for @>, built CONCURRENTLY so the index does not lock a table every write appends to." -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: VersionedUnderRoot concern (child version stamping)

**Files:**
- Create: `app/models/concerns/versioned_under_root.rb`
- Modify: `app/models/common_name.rb` (whole file, 7 lines)
- Modify: `app/models/categories_plant.rb`, `app/models/tolerances_plant.rb`, `app/models/growth_habits_plant.rb`, `app/models/antinutrients_plant.rb` (whole files, 7 lines each)
- Modify: `app/models/tolerances_variety.rb`, `app/models/growth_habits_variety.rb`, `app/models/antinutrients_variety.rb` (whole files, 7 lines each)
- Modify: `app/models/image.rb` (add include near line 5, add `versioned_under_root` block after the `enum :visibility` line, around line 17)
- Test: `spec/models/versioned_under_root_spec.rb`

**Interfaces:**
- Consumes: the GIN index from Task 1 (runtime only, not a code dependency).
- Produces:
  - `VersionedUnderRoot` concern with class macro `versioned_under_root { [root_type_string, root_id_uuid] }` (block returns `nil` to skip stamping).
  - Every version row written for `CommonName`, `CategoriesPlant`, `TolerancesPlant`, `GrowthHabitsPlant`, `AntinutrientsPlant`, `TolerancesVariety`, `GrowthHabitsVariety`, `AntinutrientsVariety`, and `Image` whose `imageable_type` is `Plant` or `Variety` carries `metadata->>'root_type'` in `{"Plant","Variety"}` and `metadata->>'root_id'` = the root uuid, IN ADDITION to whatever `origin`/`principal_id` the controller supplied.

**Steps:**

- [ ] Write the failing test at `spec/models/versioned_under_root_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

# Child rows stamp their history root into versions.metadata so a plant's
# timeline can pick them up with one containment query.
#
# The controller supplies metadata too (origin, principal_id) through
# PaperTrail.request.controller_info, and paper_trail 17 lets controller info
# REPLACE a model-level meta: value for the same key. These examples pin the
# requirement that both survive.
RSpec.describe VersionedUnderRoot, type: :model do
  def versions_for(record)
    PaperTrail::Version.where(item_type: record.class.name, item_id: record.id).order(:id)
  end

  describe 'stamping', versioning: true do
    it 'records the plant root on a common name create' do
      plant = create(:plant)
      common_name = create(:common_name, plant: plant, name: 'Test Name')

      metadata = versions_for(common_name).last.metadata
      expect(metadata['root_type']).to eq 'Plant'
      expect(metadata['root_id']).to eq plant.id
    end

    it 'keeps the controller metadata alongside the root reference' do
      principal = create(:principal)
      plant = create(:plant)

      common_name = nil
      PaperTrail.request(
        whodunnit: principal.id,
        controller_info: { metadata: { origin: 'api', principal_id: principal.id } }
      ) do
        common_name = create(:common_name, plant: plant)
      end

      metadata = versions_for(common_name).last.metadata
      expect(metadata['origin']).to eq 'api'
      expect(metadata['principal_id']).to eq principal.id
      expect(metadata['root_type']).to eq 'Plant'
      expect(metadata['root_id']).to eq plant.id
    end

    it 'records the plant root when a join row is destroyed' do
      plant = create(:plant)
      category = create(:category)
      link = CategoriesPlant.create!(plant: plant, category: category)
      link.destroy!

      destroy_version = PaperTrail::Version
                        .where(item_type: 'CategoriesPlant', item_id: link.id, event: 'destroy')
                        .last
      expect(destroy_version.metadata['root_type']).to eq 'Plant'
      expect(destroy_version.metadata['root_id']).to eq plant.id
    end

    it 'records the variety root on a variety join row' do
      variety = create(:variety)
      tolerance = create(:tolerance)
      link = TolerancesVariety.create!(variety: variety, tolerance: tolerance)

      metadata = versions_for(link).last.metadata
      expect(metadata['root_type']).to eq 'Variety'
      expect(metadata['root_id']).to eq variety.id
    end

    it 'records the plant root for an image attached to a plant' do
      plant = create(:plant)
      image = create(:image, imageable: plant)

      metadata = versions_for(image).last.metadata
      expect(metadata['root_type']).to eq 'Plant'
      expect(metadata['root_id']).to eq plant.id
    end

    it 'leaves images on other parents unstamped' do
      specimen = create(:specimen)
      image = create(:image, imageable: specimen)

      expect(versions_for(image).last.metadata).to be_blank
    end
  end
end
```
- [ ] Run `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/models/versioned_under_root_spec.rb`. Expect 5 failures with `NameError: uninitialized constant VersionedUnderRoot` (the whole describe block fails to load its described_class).
- [ ] Create `app/models/concerns/versioned_under_root.rb`:
```ruby
# frozen_string_literal: true

# Stamps { root_type, root_id } into the metadata of every PaperTrail version a
# child row produces, so the aggregated history for a plant or variety can pick
# its children up with one indexed containment lookup (see the GIN index on
# versions.metadata).
#
# Why the stamp is merged in AFTER PaperTrail writes the row, instead of using
# the model-level `meta:` option:
#
#   paper_trail 17 builds a version's attributes in
#   PaperTrail::Events::Base#merge_metadata_into, which runs
#   merge_metadata_from_model_into(data) first (assigning each model `meta:`
#   entry into data) and then returns
#   data.merge(PaperTrail.request.controller_info || {}).
#
#   Both the controller (ApplicationController#info_for_paper_trail returns
#   { metadata: { origin:, principal_id: } }) and any model `meta:` option would
#   target the same `metadata` column, and the controller's hash wins outright.
#   A `meta: { metadata: -> { ... } }` lambda would therefore lose root_type and
#   root_id on every request that carries controller info, which is every API
#   write. Merging into the stored jsonb afterwards is the only shape that keeps
#   the controller's provenance AND the root reference.
#
# Cost: one extra SELECT plus one UPDATE per child version. Child writes are
# rare next to reads, and the alternative loses data.
module VersionedUnderRoot
  extend ActiveSupport::Concern

  class_methods do
    # Declares how this model finds its history root. The block is evaluated in
    # instance context and must return [root_type_string, root_id] or nil.
    def versioned_under_root(&block)
      define_method(:paper_trail_root_ref, &block)
      private :paper_trail_root_ref
    end
  end

  included do
    after_create  :stamp_paper_trail_root
    after_update  :stamp_paper_trail_root
    after_destroy :stamp_paper_trail_root
  end

  private

  # PaperTrail records the destroy version in a before_destroy callback and the
  # create/update versions in after_ callbacks registered on ApplicationRecord,
  # which is earlier than this concern's callbacks in every case. The row we
  # stamp therefore always exists by the time this runs.
  def stamp_paper_trail_root
    return unless PaperTrail.enabled? && PaperTrail.request.enabled?

    ref = paper_trail_root_ref
    return if ref.nil?

    root_type, root_id = ref
    return if root_type.blank? || root_id.blank?

    version_id = PaperTrail::Version
                 .where(item_type: self.class.base_class.name, item_id: id)
                 .order(id: :desc)
                 .limit(1)
                 .pick(:id)
    return if version_id.nil?

    PaperTrail::Version.where(id: version_id).update_all(
      [
        "metadata = COALESCE(metadata, '{}'::jsonb) || CAST(? AS jsonb)",
        { root_type: root_type, root_id: root_id }.to_json
      ]
    )
  end
end
```
- [ ] Rewrite `app/models/common_name.rb` in full:
```ruby
# frozen_string_literal: true

# Defines the Common Name type as a related attribute of plants
class CommonName < ApplicationRecord
  include VersionedUnderRoot

  belongs_to :plant
  validates :name, :language, :plant, presence: true

  versioned_under_root { ['Plant', plant_id] }
end
```
- [ ] Rewrite the four plant join models in full, each following this shape (`app/models/categories_plant.rb` shown; do the same for `tolerances_plant.rb` with `class TolerancesPlant` + `belongs_to :tolerance`, `growth_habits_plant.rb` with `class GrowthHabitsPlant` + `belongs_to :growth_habit`, `antinutrients_plant.rb` with `class AntinutrientsPlant` + `belongs_to :antinutrient`; keep each file's existing top comment):
```ruby
# frozen_string_literal: true

# Relation table for Categories and Plants
class CategoriesPlant < ApplicationRecord
  include VersionedUnderRoot

  belongs_to :category
  belongs_to :plant

  versioned_under_root { ['Plant', plant_id] }
end
```
- [ ] Rewrite the three variety join models the same way (`app/models/tolerances_variety.rb` shown; do the same for `growth_habits_variety.rb` with `class GrowthHabitsVariety` + `belongs_to :growth_habit`, `antinutrients_variety.rb` with `class AntinutrientsVariety` + `belongs_to :antinutrient`):
```ruby
# frozen_string_literal: true

# Relation table for Tolerances and Varieties
class TolerancesVariety < ApplicationRecord
  include VersionedUnderRoot

  belongs_to :tolerance
  belongs_to :variety

  versioned_under_root { ['Variety', variety_id] }
end
```
- [ ] Modify `app/models/image.rb`: add `include VersionedUnderRoot` immediately after `class Image < ApplicationRecord` (before `extend Mobility`, around line 5), and add the root declaration immediately after the `enum :visibility, ...` line (around line 17):
```ruby
  # Images hang off many parents; only plant and variety images belong in a
  # record history timeline. Read the columns rather than the association so
  # this still works in after_destroy.
  versioned_under_root do
    %w[Plant Variety].include?(imageable_type) ? [imageable_type, imageable_id] : nil
  end
```
- [ ] Run `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/models/versioned_under_root_spec.rb`. Expect `6 examples, 0 failures`.
- [ ] Run the surrounding suites for regressions: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/models spec/mutations`. Expect 0 failures.
- [ ] Run `docker compose run --rm web bundle exec rubocop`. Expect `no offenses detected`.
- [ ] Commit:
```bash
git add app/models/concerns/versioned_under_root.rb app/models/common_name.rb app/models/image.rb app/models/categories_plant.rb app/models/tolerances_plant.rb app/models/growth_habits_plant.rb app/models/antinutrients_plant.rb app/models/tolerances_variety.rb app/models/growth_habits_variety.rb app/models/antinutrients_variety.rb spec/models/versioned_under_root_spec.rb
git commit -m "Stamp the history root into child version metadata" -m "Common names, the plant/variety join rows and plant/variety images now record { root_type, root_id } in versions.metadata so one containment query returns a record's whole timeline. The stamp is merged into the stored jsonb after PaperTrail writes the row because paper_trail 17 lets controller_info replace a model meta: value for the same key, which would drop the root reference on every API write." -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: History query and actor resolution services

**Files:**
- Create: `app/services/change_history/query.rb`
- Create: `app/services/change_history/actor_resolver.rb`
- Test: `spec/services/change_history/query_spec.rb`
- Test: `spec/services/change_history/actor_resolver_spec.rb`

**Interfaces:**
- Consumes: the `root_type`/`root_id` metadata stamp from Task 2.
- Produces:
  - `ChangeHistory::Query.new(record)` with `#relation -> ActiveRecord::Relation` of `PaperTrail::Version` ordered `created_at DESC, id DESC`.
  - `ChangeHistory::Query.newest_version_id(item_type, item_id) -> Integer | nil` (class method).
  - `ChangeHistory::ActorResolver.new` with `#principal_for(version) -> Principal | nil` and `#label_for(version) -> String` (never nil). Instances memoize lookups and are meant to live for one GraphQL request.

**Steps:**

- [ ] Write the failing test at `spec/services/change_history/query_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChangeHistory::Query do
  describe '#relation', versioning: true do
    it "returns the record's own versions newest first" do
      plant = create(:plant, scientific_name: 'One')
      plant.update!(scientific_name: 'Two')

      ids = described_class.new(plant).relation.pluck(:id)
      expect(ids).to eq ids.sort.reverse
      expect(ids.size).to eq 2
    end

    it 'includes child versions stamped with this root' do
      plant = create(:plant)
      common_name = create(:common_name, plant: plant)

      relation = described_class.new(plant).relation
      expect(relation.where(item_type: 'CommonName', item_id: common_name.id)).to exist
    end

    it 'excludes another record history' do
      plant = create(:plant)
      other = create(:plant)
      create(:common_name, plant: other)

      item_ids = described_class.new(plant).relation.pluck(:item_id)
      expect(item_ids).to all(eq(plant.id))
    end

    it 'excludes touch versions that recorded no changes' do
      plant = create(:plant)
      before_count = described_class.new(plant).relation.count
      plant.touch

      expect(described_class.new(plant).relation.count).to eq before_count
    end

    it 'works for a variety root' do
      variety = create(:variety)
      variety.update!(has_edible_green_leaves: true)

      expect(described_class.new(variety).relation.count).to eq 2
    end
  end

  describe '.newest_version_id', versioning: true do
    it 'returns the highest version id for the item' do
      plant = create(:plant, scientific_name: 'One')
      plant.update!(scientific_name: 'Two')

      expected = PaperTrail::Version.where(item_type: 'Plant', item_id: plant.id).maximum(:id)
      expect(described_class.newest_version_id('Plant', plant.id)).to eq expected
    end

    it 'returns nil when the item has no versions' do
      expect(described_class.newest_version_id('Plant', SecureRandom.uuid)).to be_nil
    end
  end
end
```
- [ ] Run `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/services/change_history/query_spec.rb`. Expect failure `NameError: uninitialized constant ChangeHistory`.
- [ ] Create `app/services/change_history/query.rb`:
```ruby
# frozen_string_literal: true

module ChangeHistory
  # Builds the aggregated version feed for one root record (a Plant or a
  # Variety): the record's own versions plus every child version that
  # VersionedUnderRoot stamped with this root.
  class Query
    # A touch (Image belongs_to :imageable, touch: true) records a version with
    # no object_changes at all, because rails' touch does no dirty tracking.
    # Those rows carry nothing a reader can see, so they are filtered in SQL --
    # before pagination, so totalCount matches what is rendered.
    NO_CHANGE_NOISE_SQL = "NOT (versions.event = 'update' AND versions.object_changes IS NULL)"

    def self.newest_version_id(item_type, item_id)
      PaperTrail::Version.where(item_type: item_type, item_id: item_id).maximum(:id)
    end

    def initialize(record)
      @root_type = record.class.base_class.name
      @root_id = record.id
    end

    def relation
      own = PaperTrail::Version.where(item_type: @root_type, item_id: @root_id)
      children = PaperTrail::Version.where('versions.metadata @> CAST(? AS jsonb)', root_match_json)

      own.or(children).where(NO_CHANGE_NOISE_SQL).order(created_at: :desc, id: :desc)
    end

    private

    def root_match_json
      { root_type: @root_type, root_id: @root_id }.to_json
    end
  end
end
```
- [ ] Run `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/services/change_history/query_spec.rb`. Expect `7 examples, 0 failures`.
- [ ] Write the failing test at `spec/services/change_history/actor_resolver_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChangeHistory::ActorResolver, versioning: true do
  subject(:resolver) { described_class.new }

  def version_for(plant)
    PaperTrail::Version.where(item_type: 'Plant', item_id: plant.id).order(:id).last
  end

  it 'resolves the principal named in metadata.principal_id' do
    principal = create(:principal, display_name: 'Data Steward')
    plant = create(:plant)
    PaperTrail.request(controller_info: { metadata: { origin: 'api', principal_id: principal.id } }) do
      plant.update!(scientific_name: 'Changed')
    end

    version = version_for(plant)
    expect(resolver.principal_for(version)).to eq principal
    expect(resolver.label_for(version)).to eq 'Data Steward'
  end

  it 'resolves a whodunnit that is itself a principal id (sync writes)' do
    principal = create(:principal, :service, display_name: 'Import Service')
    plant = create(:plant)
    PaperTrail.request(whodunnit: principal.id, controller_info: { metadata: { origin: 'sync' } }) do
      plant.update!(scientific_name: 'Synced')
    end

    version = version_for(plant)
    expect(resolver.principal_for(version)).to eq principal
    expect(resolver.label_for(version)).to eq 'Import Service'
  end

  it 'resolves a whodunnit that is a JWT uid' do
    principal = create(:principal, display_name: nil, external_uid: SecureRandom.uuid)
    plant = create(:plant)
    PaperTrail.request(whodunnit: principal.external_uid) do
      plant.update!(scientific_name: 'By uid')
    end

    version = version_for(plant)
    expect(resolver.principal_for(version)).to eq principal
    expect(resolver.label_for(version)).to eq principal.email
  end

  it 'falls back to a label when nothing resolves' do
    plant = create(:plant)
    PaperTrail.request(whodunnit: 'sandbox') do
      plant.update!(scientific_name: 'Anonymous')
    end

    version = version_for(plant)
    expect(resolver.principal_for(version)).to be_nil
    expect(resolver.label_for(version)).to eq described_class::UNKNOWN_LABEL
  end

  it 'labels unattributed sync writes as an automated import' do
    plant = create(:plant)
    PaperTrail.request(controller_info: { metadata: { origin: 'sync' } }) do
      plant.update!(scientific_name: 'Machine')
    end

    version = version_for(plant)
    expect(resolver.label_for(version)).to eq described_class::SYNC_LABEL
  end

  it 'queries once per distinct actor' do
    principal = create(:principal)
    plant = create(:plant)
    PaperTrail.request(controller_info: { metadata: { principal_id: principal.id } }) do
      plant.update!(scientific_name: 'A')
      plant.update!(scientific_name: 'B')
    end

    versions = PaperTrail::Version.where(item_type: 'Plant', item_id: plant.id).order(:id).to_a
    allow(Principal).to receive(:find_by).and_call_original
    versions.each { |version| resolver.principal_for(version) }

    expect(Principal).to have_received(:find_by).once
  end
end
```
- [ ] Run `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/services/change_history/actor_resolver_spec.rb`. Expect failure `NameError: uninitialized constant ChangeHistory::ActorResolver`.
- [ ] Create `app/services/change_history/actor_resolver.rb`:
```ruby
# frozen_string_literal: true

module ChangeHistory
  # Resolves the acting identity behind a version row.
  #
  # Resolution order (design spec): metadata.principal_id, then whodunnit read
  # as a principal id (what the sync writer stores), then whodunnit read as an
  # external JWT uid, then a fallback label.
  #
  # One instance is created per GraphQL request and memoizes every lookup, so a
  # page of entries written by the same person costs a single query. Raw uids
  # are never surfaced as a label: they identify a person without naming one.
  class ActorResolver
    UNKNOWN_LABEL = 'Unknown user'
    SYNC_LABEL = 'Automated import'
    UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

    def initialize
      @by_id = {}
      @by_uid = {}
    end

    def principal_for(version)
      principal_id = metadata(version)['principal_id']
      return find_by_id(principal_id) if principal_id.present?

      whodunnit = version.whodunnit
      return nil if whodunnit.blank?

      find_by_id(whodunnit) || find_by_uid(whodunnit)
    end

    def label_for(version)
      principal = principal_for(version)
      if principal
        return principal.display_name.presence || principal.email.presence || UNKNOWN_LABEL
      end

      metadata(version)['origin'] == 'sync' ? SYNC_LABEL : UNKNOWN_LABEL
    end

    private

    def metadata(version)
      version.metadata.is_a?(Hash) ? version.metadata : {}
    end

    # principals.id is a uuid column: handing it a JWT uid that is not a uuid
    # would raise a StatementInvalid rather than return nil.
    def find_by_id(value)
      return nil unless value.to_s.match?(UUID_FORMAT)

      @by_id.fetch(value) { @by_id[value] = Principal.find_by(id: value) }
    end

    def find_by_uid(value)
      @by_uid.fetch(value) { @by_uid[value] = Principal.find_by(external_uid: value) }
    end
  end
end
```
- [ ] Run `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/services/change_history/actor_resolver_spec.rb`. Expect `6 examples, 0 failures`.
- [ ] Run `docker compose run --rm web bundle exec rubocop`. Expect `no offenses detected`.
- [ ] Commit:
```bash
git add app/services/change_history/query.rb app/services/change_history/actor_resolver.rb spec/services/change_history/query_spec.rb spec/services/change_history/actor_resolver_spec.rb
git commit -m "Add the record history query and actor resolution services" -m "ChangeHistory::Query unions a record's own versions with the child versions stamped under its root and drops information-free touch versions. ChangeHistory::ActorResolver walks metadata.principal_id, whodunnit-as-principal-id and whodunnit-as-uid, memoized for the life of one request." -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Diff builder and subject resolution

**Files:**
- Create: `app/services/change_history/diff_builder.rb`
- Create: `app/services/change_history/subject.rb`
- Test: `spec/services/change_history/diff_builder_spec.rb`
- Test: `spec/services/change_history/subject_spec.rb`

**Interfaces:**
- Consumes: `PaperTrail::Version` rows produced under Task 2.
- Produces:
  - `ChangeHistory::DiffBuilder.new(version).call -> Array<Hash>` where each hash is exactly `{ field: String, locale: String | nil, before: String | nil, after: String | nil }` with symbol keys, `field` in lowerCamelCase.
  - `ChangeHistory::Subject.new(version)` with `#subject_type -> String` (one of `record common_name category tolerance growth_habit antinutrient image`) and `#label -> String | nil`.

**Steps:**

- [ ] Write the failing test at `spec/services/change_history/diff_builder_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChangeHistory::DiffBuilder, versioning: true do
  def last_version(record)
    PaperTrail::Version.where(item_type: record.class.name, item_id: record.id).order(:id).last
  end

  def build(record)
    described_class.new(last_version(record)).call
  end

  it 'renders a scalar column change under its camelCase graphql name' do
    plant = create(:plant, scientific_name: 'Old Name')
    plant.update!(scientific_name: 'New Name')

    expect(build(plant)).to include(
      { field: 'scientificName', locale: nil, before: 'Old Name', after: 'New Name' }
    )
  end

  it 'renders booleans as true/false' do
    plant = create(:plant, has_edible_green_leaves: false)
    plant.update!(has_edible_green_leaves: true)

    expect(build(plant)).to include(
      { field: 'hasEdibleGreenLeaves', locale: nil, before: 'false', after: 'true' }
    )
  end

  it 'renders enums as their graphql names' do
    plant = create(:plant, life_cycle: 'annual')
    plant.update!(life_cycle: 'perennial')

    expect(build(plant)).to include(
      { field: 'lifeCycle', locale: nil, before: 'ANNUAL', after: 'PERENNIAL' }
    )
  end

  it 'renders ranges as postgres range literals' do
    plant = create(:plant, ph_range: '[1.0,2.0]')
    plant.update!(ph_range: '[3.0,4.0]')

    change = build(plant).find { |c| c[:field] == 'phRange' }
    expect(change[:before]).to eq '[1.0,2.0]'
    expect(change[:after]).to eq '[3.0,4.0]'
  end

  it 'renders visibility as its enum name' do
    plant = create(:plant, :private)
    plant.update!(visibility: :public)

    expect(build(plant)).to include(
      { field: 'visibility', locale: nil, before: 'PRIVATE', after: 'PUBLIC' }
    )
  end

  it 'flattens translations into one entry per locale and attribute' do
    plant = create(:plant)
    Mobility.with_locale(:es) { plant.update!(uses: 'Usos nuevos') }

    expect(build(plant)).to include(
      { field: 'uses', locale: 'es', before: nil, after: 'Usos nuevos' }
    )
  end

  it 'skips noise columns' do
    plant = create(:plant, scientific_name: 'Old Name')
    plant.update!(scientific_name: 'New Name')

    fields = build(plant).map { |c| c[:field] }
    expect(fields).not_to include('updatedAt', 'createdAt', 'translations', 'publicationState')
  end

  it 'returns an empty list for a version with no parsable changes' do
    plant = create(:plant)
    version = last_version(plant)
    version.update_columns(object_changes: nil)

    expect(described_class.new(version).call).to eq []
  end
end
```
- [ ] Run `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/services/change_history/diff_builder_spec.rb`. Expect failure `NameError: uninitialized constant ChangeHistory::DiffBuilder`.
- [ ] Create `app/services/change_history/diff_builder.rb`:
```ruby
# frozen_string_literal: true

module ChangeHistory
  # Turns a version's object_changes into the field-level diff the API renders.
  #
  # Column names become the camelCase graphql field names, values are humanized
  # (ranges as postgres literals, enums as their graphql names, booleans as
  # true/false), and the Mobility container column is flattened into one entry
  # per locale and attribute.
  #
  # Ownership and visibility changes are deliberately KEPT: they are meaningful
  # audit events. The dual-write mirrors of visibility (publication_state,
  # access_level, deleted_at, deleted_by_principal_id) are skipped instead,
  # because reporting the same transition three times is noise.
  class DiffBuilder
    SKIPPED_COLUMNS = %w[
      id created_at updated_at translations
      plant_id variety_id imageable_id imageable_type
      category_id tolerance_id growth_habit_id antinutrient_id
      publication_state access_level deleted_at deleted_by_principal_id
      data_source_id source_record_id source_updated_at last_synced_at
      source_digest sync_state source_snapshot
    ].freeze

    # Frozen legacy contract, mirrored here so the builder never has to
    # constantize an item_type to read an enum.
    VISIBILITY_NAMES = { 0 => 'PRIVATE', 1 => 'PUBLIC', 2 => 'DRAFT', 3 => 'DELETED' }.freeze

    ENUM_COLUMNS = %w[early_growth_phase life_cycle].freeze

    def initialize(version)
      @version = version
    end

    def call
      changeset = safe_changeset
      return [] if changeset.blank?

      column_changes(changeset) + translation_changes(changeset)
    end

    private

    # Years-old history can contain payloads the safe YAML serializer refuses.
    # A timeline entry that cannot be parsed is rendered without a diff rather
    # than failing the whole query.
    def safe_changeset
      @version.changeset
    rescue StandardError => e
      Rails.logger.warn("ChangeHistory::DiffBuilder skipped version #{@version.id}: #{e.class}")
      nil
    end

    def column_changes(changeset)
      changeset.filter_map do |column, (before, after)|
        next if SKIPPED_COLUMNS.include?(column)

        rendered_before = format_value(column, before)
        rendered_after  = format_value(column, after)
        next if rendered_before == rendered_after

        { field: column.camelize(:lower), locale: nil, before: rendered_before, after: rendered_after }
      end
    end

    def translation_changes(changeset)
      before, after = changeset['translations']
      before = before.is_a?(Hash) ? before : {}
      after  = after.is_a?(Hash) ? after : {}

      (before.keys | after.keys).sort.flat_map do |locale|
        locale_changes(locale, before[locale] || {}, after[locale] || {})
      end
    end

    def locale_changes(locale, before, after)
      (before.keys | after.keys).sort.filter_map do |attribute|
        old_value = presence_of(before[attribute])
        new_value = presence_of(after[attribute])
        next if old_value == new_value

        { field: attribute.camelize(:lower), locale: locale, before: old_value, after: new_value }
      end
    end

    def presence_of(value)
      value.nil? ? nil : value.to_s
    end

    def format_value(column, value)
      return nil if value.nil?
      return VISIBILITY_NAMES[value.to_i] if column == 'visibility'
      return value.to_s.upcase if ENUM_COLUMNS.include?(column)

      case value
      when Range then range_literal(value)
      when true, false then value.to_s
      when Time, DateTime, Date then value.iso8601
      else value.to_s
      end
    end

    def range_literal(value)
      "[#{value.begin},#{value.end}#{value.exclude_end? ? ')' : ']'}"
    end
  end
end
```
- [ ] Run `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/services/change_history/diff_builder_spec.rb`. Expect `8 examples, 0 failures`.
- [ ] Write the failing test at `spec/services/change_history/subject_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChangeHistory::Subject, versioning: true do
  def last_version(record)
    PaperTrail::Version.where(item_type: record.class.name, item_id: record.id).order(:id).last
  end

  it 'labels the record itself' do
    plant = create(:plant)
    subject = described_class.new(last_version(plant))

    expect(subject.subject_type).to eq 'record'
    expect(subject.label).to be_nil
  end

  it 'labels a common name with its name' do
    common_name = create(:common_name, name: 'Sample Name')
    subject = described_class.new(last_version(common_name))

    expect(subject.subject_type).to eq 'common_name'
    expect(subject.label).to eq 'Sample Name'
  end

  it 'labels a deleted common name from the destroy changeset' do
    common_name = create(:common_name, name: 'Removed Name')
    common_name.destroy!
    version = PaperTrail::Version.where(item_type: 'CommonName', item_id: common_name.id, event: 'destroy').last

    subject = described_class.new(version)
    expect(subject.subject_type).to eq 'common_name'
    expect(subject.label).to eq 'Removed Name'
  end

  it 'labels a join row with the linked lookup name' do
    category = create(:category, name: 'Legumes')
    link = CategoriesPlant.create!(plant: create(:plant), category: category)

    subject = described_class.new(last_version(link))
    expect(subject.subject_type).to eq 'category'
    expect(subject.label).to eq 'Legumes'
  end

  it 'falls back to nil when the linked row is gone' do
    tolerance = create(:tolerance)
    link = TolerancesPlant.create!(plant: create(:plant), tolerance: tolerance)
    version = last_version(link)
    link.destroy!
    tolerance.destroy!

    subject = described_class.new(version)
    expect(subject.subject_type).to eq 'tolerance'
    expect(subject.label).to be_nil
  end

  it 'labels an image with its name' do
    image = create(:image, name: 'Field photo')

    subject = described_class.new(last_version(image))
    expect(subject.subject_type).to eq 'image'
    expect(subject.label).to eq 'Field photo'
  end
end
```
- [ ] Run `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/services/change_history/subject_spec.rb`. Expect failure `NameError: uninitialized constant ChangeHistory::Subject`.
- [ ] Create `app/services/change_history/subject.rb`:
```ruby
# frozen_string_literal: true

module ChangeHistory
  # Maps a version's item_type to the ChangeSubject enum value and resolves a
  # human label for child subjects: the common name text, the linked lookup
  # name, the image name. Labels are resolved at query time and degrade to nil
  # when the referenced row no longer exists.
  class Subject
    RECORD = 'record'

    SIMPLE_TYPES = {
      'Plant' => RECORD,
      'Variety' => RECORD,
      'CommonName' => 'common_name',
      'Image' => 'image'
    }.freeze

    JOIN_TYPES = {
      'CategoriesPlant' => { subject: 'category', model: Category, foreign_key: 'category_id' },
      'TolerancesPlant' => { subject: 'tolerance', model: Tolerance, foreign_key: 'tolerance_id' },
      'TolerancesVariety' => { subject: 'tolerance', model: Tolerance, foreign_key: 'tolerance_id' },
      'GrowthHabitsPlant' => { subject: 'growth_habit', model: GrowthHabit, foreign_key: 'growth_habit_id' },
      'GrowthHabitsVariety' => { subject: 'growth_habit', model: GrowthHabit, foreign_key: 'growth_habit_id' },
      'AntinutrientsPlant' => { subject: 'antinutrient', model: Antinutrient, foreign_key: 'antinutrient_id' },
      'AntinutrientsVariety' => { subject: 'antinutrient', model: Antinutrient, foreign_key: 'antinutrient_id' }
    }.freeze

    def initialize(version)
      @version = version
    end

    def subject_type
      JOIN_TYPES.dig(@version.item_type, :subject) ||
        SIMPLE_TYPES.fetch(@version.item_type, RECORD)
    end

    def label
      case subject_type
      when RECORD then nil
      when 'common_name' then changeset_value('name')
      when 'image' then Image.find_by(id: @version.item_id)&.name
      else join_label
      end
    end

    private

    def join_label
      config = JOIN_TYPES[@version.item_type]
      return nil if config.nil?

      linked_id = changeset_value(config[:foreign_key])
      return nil if linked_id.blank?

      config[:model].find_by(id: linked_id)&.name
    end

    # A create records [nil, value] and a destroy records [value, nil], so the
    # last non-nil entry is the value that names the subject in both directions.
    def changeset_value(key)
      changeset = safe_changeset
      return nil if changeset.blank?

      Array(changeset[key]).compact.last
    end

    def safe_changeset
      @version.changeset
    rescue StandardError => e
      Rails.logger.warn("ChangeHistory::Subject skipped version #{@version.id}: #{e.class}")
      nil
    end
  end
end
```
- [ ] Run `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/services/change_history/subject_spec.rb`. Expect `6 examples, 0 failures`.
- [ ] Run `docker compose run --rm web bundle exec rubocop`. Expect `no offenses detected`. If `Metrics/ClassLength` or `Metrics/MethodLength` fires on either new file, split the offending method rather than adding a `.rubocop_todo.yml` entry.
- [ ] Commit:
```bash
git add app/services/change_history/diff_builder.rb app/services/change_history/subject.rb spec/services/change_history/diff_builder_spec.rb spec/services/change_history/subject_spec.rb
git commit -m "Add the record history diff builder and subject resolver" -m "DiffBuilder maps object_changes onto camelCase graphql field names, humanizes ranges, enums, booleans and the legacy visibility integer, flattens the Mobility container column per locale, and skips the sync, timestamp and dual-write mirror columns. Subject names the child a version belongs to, degrading to nil when the referenced row is gone." -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: GraphQL types and the recordHistory field

**Files:**
- Create: `app/graphql/types/change_event_enum.rb`
- Create: `app/graphql/types/change_origin_enum.rb`
- Create: `app/graphql/types/change_subject_enum.rb`
- Create: `app/graphql/types/field_change_type.rb`
- Create: `app/graphql/types/change_entry_type.rb`
- Create: `app/graphql/types/change_entry_type/change_entry_edge_type.rb`
- Create: `app/graphql/types/change_entry_type/change_entry_connection_with_total_count_type.rb`
- Modify: `app/graphql/plant_api_schema.rb` (`NODE_FORBIDDEN_TYPES`, line 56)
- Modify: `app/graphql/types/plant_type.rb` (add field after the `field :updated_at` block ending around line 216; add resolver after `def images` around line 221)
- Modify: `app/graphql/types/variety_type.rb` (add field after the `field :updated_at` block ending around line 196; add resolver after `def images` around line 201)
- Modify: `schema.graphql` (regenerated)
- Test: `spec/queries/record_history_query_spec.rb`

**Interfaces:**
- Consumes: `ChangeHistory::Query`, `ChangeHistory::ActorResolver`, `ChangeHistory::DiffBuilder`, `ChangeHistory::Subject` from Tasks 3 and 4.
- Produces:
  - SDL: `type ChangeEntry { id: ID!, createdAt: ISO8601DateTime!, event: ChangeEvent!, origin: ChangeOrigin!, actor: Principal, actorLabel: String!, subjectType: ChangeSubject!, subjectLabel: String, changes: [FieldChange!]!, restorable: Boolean! }`, `type FieldChange { field: String!, locale: String, before: String, after: String }`, `enum ChangeEvent { CREATED UPDATED DELETED RESTORED }`, `enum ChangeOrigin { API SYNC BACKFILL }`, `enum ChangeSubject { RECORD COMMON_NAME CATEGORY TOLERANCE GROWTH_HABIT ANTINUTRIENT IMAGE }`, `type ChangeEntryConnectionWithTotalCount`.
  - `Plant.recordHistory(first:, after:, last:, before:)` and `Variety.recordHistory(...)`, `max_page_size` 50, raising `Pundit::NotAuthorizedError` unless `policy.update?`.
  - `ChangeEntry` global id format: `GraphQL::Schema::UniqueWithinType.encode('ChangeEntry', version.id)`; Task 7 decodes it.
  - `'ChangeEntry'` added to `PlantApiSchema::NODE_FORBIDDEN_TYPES`.

**Steps:**

- [ ] Write the failing test at `spec/queries/record_history_query_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'recordHistory query', type: :graphql_query do
  let(:query_string) do
    <<~GRAPHQL
      query($id: ID!) {
        plant(id: $id) {
          recordHistory(first: 10) {
            totalCount
            edges {
              node {
                id
                createdAt
                event
                origin
                actorLabel
                subjectType
                subjectLabel
                restorable
                actor { displayName }
                changes { field locale before after }
              }
            }
          }
        }
      }
    GRAPHQL
  end

  def execute(plant, user)
    PlantApiSchema.execute(
      query_string,
      context: { current_user: user },
      variables: { id: PlantApiSchema.id_from_object(plant, Plant, {}) }
    )
  end

  describe 'authorization' do
    it 'returns 401 for anonymous callers', versioning: true do
      plant = create(:plant, :public)
      result = execute(plant, nil)

      expect(result.dig('errors', 0, 'extensions', 'code')).to eq 401
    end

    it 'returns 403 for an authenticated user who cannot edit', versioning: true do
      plant = create(:plant, :public)
      result = execute(plant, build(:user, :readonly))

      expect(result.dig('errors', 0, 'extensions', 'code')).to eq 403
    end
  end

  describe 'entries', versioning: true do
    let(:user) { build(:user, :readwrite) }
    let(:plant) { create(:plant, owned_by: user.email, created_by: user.email, scientific_name: 'Before') }

    it 'returns the record entries newest first with actor and diff' do
      PaperTrail.request(
        whodunnit: user.principal.id,
        controller_info: { metadata: { origin: 'api', principal_id: user.principal.id } }
      ) do
        plant.update!(scientific_name: 'After')
      end

      history = execute(plant, user).dig('data', 'plant', 'recordHistory')
      nodes = history['edges'].map { |edge| edge['node'] }

      expect(history['totalCount']).to eq 2
      expect(nodes.first['event']).to eq 'UPDATED'
      expect(nodes.first['origin']).to eq 'API'
      expect(nodes.first['subjectType']).to eq 'RECORD'
      # The :user factory resolves a principal without a display name, so the
      # label falls through to the principal email.
      expect(nodes.first['actorLabel']).to eq user.email
      expect(nodes.first['changes']).to include(
        'field' => 'scientificName', 'locale' => nil, 'before' => 'Before', 'after' => 'After'
      )
      expect(nodes.first['restorable']).to be false
      expect(nodes.last['event']).to eq 'CREATED'
      expect(nodes.last['restorable']).to be true
    end

    it 'includes aggregated child entries' do
      create(:common_name, plant: plant, name: 'Child Entry')

      nodes = execute(plant, user).dig('data', 'plant', 'recordHistory', 'edges').map { |e| e['node'] }
      child = nodes.find { |node| node['subjectType'] == 'COMMON_NAME' }

      expect(child).not_to be_nil
      expect(child['subjectLabel']).to eq 'Child Entry'
      expect(child['event']).to eq 'CREATED'
      expect(child['restorable']).to be false
    end

    it 'gives every entry an opaque id that is not node addressable' do
      node_id = execute(plant, user).dig('data', 'plant', 'recordHistory', 'edges', 0, 'node', 'id')
      type_name, = GraphQL::Schema::UniqueWithinType.decode(node_id)
      expect(type_name).to eq 'ChangeEntry'

      probe = PlantApiSchema.execute(
        'query($id: ID!) { node(id: $id) { id } }',
        context: { current_user: user },
        variables: { id: node_id }
      )
      expect(probe.dig('errors', 0, 'extensions', 'code')).to eq 404
    end
  end
end
```
- [ ] Run `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/queries/record_history_query_spec.rb`. Expect all 5 examples to fail with a GraphQL validation error: `Field 'recordHistory' doesn't exist on type 'Plant'`.
- [ ] Create the three enums. `app/graphql/types/change_event_enum.rb`:
```ruby
# frozen_string_literal: true

module Types
  # The kind of change a history entry records.
  class ChangeEventEnum < Types::BaseEnum
    graphql_name 'ChangeEvent'
    description 'The kind of change a record history entry represents.'

    value 'CREATED', value: 'created', description: 'The row was created.'
    value 'UPDATED', value: 'updated', description: 'The row was updated.'
    value 'DELETED', value: 'deleted', description: 'The row was deleted.'
    value 'RESTORED', value: 'restored', description: 'The record was restored to an earlier state.'
  end
end
```
`app/graphql/types/change_origin_enum.rb`:
```ruby
# frozen_string_literal: true

module Types
  # Where a recorded change came from.
  class ChangeOriginEnum < Types::BaseEnum
    graphql_name 'ChangeOrigin'
    description 'Where a recorded change came from. Entries written before provenance metadata existed report API.'

    value 'API', value: 'api', description: 'A request through the GraphQL API.'
    value 'SYNC', value: 'sync', description: 'An external data source synchronization run.'
    value 'BACKFILL', value: 'backfill', description: 'A maintenance backfill.'
  end
end
```
`app/graphql/types/change_subject_enum.rb`:
```ruby
# frozen_string_literal: true

module Types
  # Which part of the record a history entry is about.
  class ChangeSubjectEnum < Types::BaseEnum
    graphql_name 'ChangeSubject'
    description 'Which part of the record a history entry is about.'

    value 'RECORD', value: 'record', description: 'The plant or variety itself.'
    value 'COMMON_NAME', value: 'common_name'
    value 'CATEGORY', value: 'category'
    value 'TOLERANCE', value: 'tolerance'
    value 'GROWTH_HABIT', value: 'growth_habit'
    value 'ANTINUTRIENT', value: 'antinutrient'
    value 'IMAGE', value: 'image'
  end
end
```
- [ ] Create `app/graphql/types/field_change_type.rb`:
```ruby
# frozen_string_literal: true

module Types
  # One field-level before/after pair inside a change entry. Values are rendered
  # server-side: ranges as postgres literals, enums as their graphql names,
  # booleans as true/false.
  class FieldChangeType < Types::BaseObject
    description 'A single field level change, with server-rendered values.'

    field :field, String, null: false, hash_key: :field,
                          description: 'The camelCase graphql name of the changed field.'
    field :locale, String, null: true, hash_key: :locale,
                           description: 'The locale of a translated field, or null for untranslated fields.'
    field :before, String, null: true, hash_key: :before
    field :after, String, null: true, hash_key: :after
  end
end
```
- [ ] Create `app/graphql/types/change_entry_type.rb`:
```ruby
# frozen_string_literal: true

module Types
  # One entry in a record history timeline. The underlying object is a
  # PaperTrail::Version; every presented value is computed by the ChangeHistory
  # services. Never node addressable (see PlantApiSchema::NODE_FORBIDDEN_TYPES):
  # entries are only reachable through an already authorized parent record.
  class ChangeEntryType < Types::BaseObject
    description 'One recorded change to a record or one of its child rows.'

    KNOWN_ORIGINS = %w[api sync backfill].freeze

    field :id, ID, null: false,
                   description: 'Opaque id for this entry. Pass it to restorePlantVersion or restoreVarietyVersion.'
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false,
                                                        description: 'When the change was recorded.'
    field :event, Types::ChangeEventEnum, null: false
    field :origin, Types::ChangeOriginEnum, null: false
    field :actor, Types::PrincipalType, null: true,
                                        description: 'The identity behind the change, when it can be resolved.'
    field :actor_label, String, null: false,
                                description: 'Always-present display label for the actor.'
    field :subject_type, Types::ChangeSubjectEnum, null: false
    field :subject_label, String, null: true,
                                  description: 'Name of the child row this entry is about, when it can be resolved.'
    field :changes, [Types::FieldChangeType], null: false
    field :restorable, Boolean, null: false,
                                description: 'True when this entry can be restored with a restore-version mutation.'

    def id
      GraphQL::Schema::UniqueWithinType.encode('ChangeEntry', object.id)
    end

    def event
      return 'restored' if metadata['restored_from_version_id'].present?

      case object.event
      when 'create' then 'created'
      when 'destroy' then 'deleted'
      else 'updated'
      end
    end

    # Rows written before provenance metadata existed carry no origin.
    def origin
      value = metadata['origin'].to_s
      KNOWN_ORIGINS.include?(value) ? value : 'api'
    end

    def actor
      actor_resolver.principal_for(object)
    end

    def actor_label
      actor_resolver.label_for(object)
    end

    def subject_type
      subject.subject_type
    end

    def subject_label
      subject.label
    end

    def changes
      ChangeHistory::DiffBuilder.new(object).call
    end

    # Restoring an entry means reifying the version that FOLLOWS it, so the
    # newest entry for a record has nothing to restore from. Child subjects are
    # out of scope for v1.
    def restorable
      return false unless subject.subject_type == ChangeHistory::Subject::RECORD

      newest = newest_version_id
      newest.present? && object.id < newest
    end

    private

    def metadata
      object.metadata.is_a?(Hash) ? object.metadata : {}
    end

    def subject
      @subject ||= ChangeHistory::Subject.new(object)
    end

    # One resolver per request keeps actor lookups to one query per distinct
    # identity across the whole page.
    def actor_resolver
      context[:change_history_actor_resolver] ||= ChangeHistory::ActorResolver.new
    end

    def newest_version_id
      cache = (context[:change_history_newest_version_id] ||= {})
      key = [object.item_type, object.item_id]
      cache.fetch(key) do
        cache[key] = ChangeHistory::Query.newest_version_id(object.item_type, object.item_id)
      end
    end
  end
end
```
- [ ] Create `app/graphql/types/change_entry_type/change_entry_edge_type.rb`:
```ruby
# frozen_string_literal: true

module Types
  class ChangeEntryType
    # The edge type for the change entry type
    class ChangeEntryEdgeType < GraphQL::Types::Relay::BaseEdge
      node_type(Types::ChangeEntryType)
    end
  end
end
```
- [ ] Create `app/graphql/types/change_entry_type/change_entry_connection_with_total_count_type.rb`:
```ruby
# frozen_string_literal: true

module Types
  class ChangeEntryType
    # Adds a total_count field to the change entry connection
    class ChangeEntryConnectionWithTotalCountType < GraphQL::Types::Relay::BaseConnection
      edge_type(ChangeEntryEdgeType)

      field :total_count, Integer, null: false
      def total_count
        object.items.size
      end
    end
  end
end
```
- [ ] Modify `app/graphql/plant_api_schema.rb` line 56 so the constant reads:
```ruby
  NODE_FORBIDDEN_TYPES = %w[Principal Organization DataSource SyncConflict ChangeEntry].freeze
```
- [ ] Modify `app/graphql/types/plant_type.rb`: insert this field immediately after the `field :updated_at ...` block (before the commented-out `# field :versions` line, around line 217):
```ruby
    field :record_history, Types::ChangeEntryType::ChangeEntryConnectionWithTotalCountType,
          description: 'Audit timeline for this plant and its common names, relation links and images, newest first. Visible only to users who may edit the plant.',
          null: true,
          connection: true,
          max_page_size: 50
```
and insert this resolver immediately after the `def images ... end` method (around line 221):
```ruby
    # Actor identity is sensitive, so history is gated by the same policy that
    # gates editing. Raising here lets the schema-level rescue render the
    # standard 401/403.
    def record_history
      unless resolved_policy.update?
        raise Pundit::NotAuthorizedError.new(query: :update?, record: @object, policy: nil)
      end

      ChangeHistory::Query.new(@object).relation
    end
```
- [ ] Modify `app/graphql/types/variety_type.rb` the same way: the field goes after the `field :updated_at ...` block (around line 197) with `plant` replaced by `variety` in the description, and the identical `record_history` resolver goes after `def images ... end` (around line 202).
- [ ] Run `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/queries/record_history_query_spec.rb`. Expect `5 examples, 0 failures`.
- [ ] Regenerate the SDL: `docker compose run --rm -e RAILS_ENV=test web bundle exec rails graphql:schema:dump`. Expect `git diff --stat schema.graphql` to show only additions (new ChangeEntry/FieldChange/ChangeEvent/ChangeOrigin/ChangeSubject/ChangeEntryConnectionWithTotalCount/ChangeEntryEdge definitions plus the two `recordHistory` fields).
- [ ] Run the full suite: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec`. Expect 0 failures (baseline 1943 plus the specs added so far).
- [ ] Run `docker compose run --rm web bundle exec rubocop`. Expect `no offenses detected`.
- [ ] Commit:
```bash
git add app/graphql/types/change_event_enum.rb app/graphql/types/change_origin_enum.rb app/graphql/types/change_subject_enum.rb app/graphql/types/field_change_type.rb app/graphql/types/change_entry_type.rb app/graphql/types/change_entry_type app/graphql/plant_api_schema.rb app/graphql/types/plant_type.rb app/graphql/types/variety_type.rb schema.graphql spec/queries/record_history_query_spec.rb
git commit -m "Expose recordHistory on plants and varieties" -m "A ChangeEntry connection over the aggregated version feed, with server-computed diffs, resolved actors and child subject labels. The field is gated by the update? policy because actor identity is sensitive, and ChangeEntry is not node addressable." -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Restore service

**Files:**
- Create: `app/services/change_history/restorer.rb`
- Test: `spec/services/change_history/restorer_spec.rb`

**Interfaces:**
- Consumes: `ChangeHistory::Query.newest_version_id`, `Mutations::Concerns::PlantEditableArguments::BOOLEAN_FIELDS`, `Mutations::Concerns::VarietyEditableArguments::BOOLEAN_FIELDS`, `Mutations::Concerns::RangeLiteralValidation::RANGE_FIELDS`.
- Produces:
  - `ChangeHistory::Restorer.new(record:, version_id:).call -> ChangeHistory::Restorer::Result`.
  - `Result` is `Struct.new(:record, :errors, keyword_init: true)`; `errors` is an array of payload-error hashes `{ field: 'versionId', message: String, code: Integer }` and is empty when the restore was attempted (validation failures are left on `record.errors` for the mutation to convert).
  - `ChangeHistory::Restorer::RESTORABLE_ATTRIBUTES` (Hash of `'Plant' | 'Variety'` to a frozen array of column names).

**Steps:**

- [ ] Write the failing test at `spec/services/change_history/restorer_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChangeHistory::Restorer, versioning: true do
  def versions_for(record)
    PaperTrail::Version.where(item_type: record.class.name, item_id: record.id).order(:id)
  end

  describe 'a plant restore' do
    let(:plant) { create(:plant, scientific_name: 'Original', has_edible_green_leaves: false) }

    it 'restores the state immediately after the chosen entry' do
      create_version = versions_for(plant).first
      plant.update!(scientific_name: 'Second')
      plant.update!(scientific_name: 'Third')

      result = described_class.new(record: plant, version_id: create_version.id).call

      expect(result.errors).to be_empty
      expect(plant.reload.scientific_name).to eq 'Original'
    end

    it 'restores translated values' do
      Mobility.with_locale(:en) { plant.update!(uses: 'First use') }
      target = versions_for(plant).last
      Mobility.with_locale(:en) { plant.update!(uses: 'Second use') }

      described_class.new(record: plant, version_id: target.id).call

      expect(Mobility.with_locale(:en) { plant.reload.uses }).to eq 'First use'
    end

    it 'records the restore as a new version stamped with the source version' do
      create_version = versions_for(plant).first
      plant.update!(scientific_name: 'Second')

      expect { described_class.new(record: plant, version_id: create_version.id).call }
        .to change { versions_for(plant).count }.by(1)

      expect(versions_for(plant).last.metadata['restored_from_version_id']).to eq create_version.id
    end

    it 'keeps the controller provenance metadata on the restore version' do
      principal = create(:principal)
      create_version = versions_for(plant).first
      plant.update!(scientific_name: 'Second')

      PaperTrail.request(controller_info: { metadata: { origin: 'api', principal_id: principal.id } }) do
        described_class.new(record: plant, version_id: create_version.id).call
      end

      metadata = versions_for(plant).last.metadata
      expect(metadata['origin']).to eq 'api'
      expect(metadata['principal_id']).to eq principal.id
      expect(metadata['restored_from_version_id']).to eq create_version.id
    end

    it 'never touches ownership, visibility or sync columns' do
      create_version = versions_for(plant).first
      plant.update!(scientific_name: 'Second', visibility: :public)
      owner = plant.owner_organization_id
      creator = plant.created_by_principal_id

      described_class.new(record: plant, version_id: create_version.id).call
      plant.reload

      expect(plant.visibility).to eq 'public'
      expect(plant.owner_organization_id).to eq owner
      expect(plant.created_by_principal_id).to eq creator
      expect(plant.owned_by).to be_present
    end

    it 'refuses the newest entry' do
      plant.update!(scientific_name: 'Second')
      newest = versions_for(plant).last

      result = described_class.new(record: plant, version_id: newest.id).call

      expect(result.errors.first).to include(field: 'versionId', code: 400)
      expect(result.errors.first[:message]).to match(/already the current state/i)
    end

    it 'refuses a soft-deleted record' do
      create_version = versions_for(plant).first
      plant.update!(scientific_name: 'Second')
      plant.update!(visibility: :deleted)

      result = described_class.new(record: plant, version_id: create_version.id).call

      expect(result.errors.first).to include(field: 'versionId', code: 400)
      expect(result.errors.first[:message]).to match(/trash/i)
    end

    it 'refuses a version that belongs to another record' do
      other = create(:plant)
      other.update!(scientific_name: 'Elsewhere')
      foreign = versions_for(other).last

      result = described_class.new(record: plant, version_id: foreign.id).call

      expect(result.errors.first).to include(field: 'versionId', code: 404)
    end

    it 'leaves validation failures on the record' do
      create_version = versions_for(plant).first
      plant.update!(scientific_name: 'Second')
      allow(plant).to receive(:update) do
        plant.errors.add(:scientific_name, 'is invalid')
        false
      end

      result = described_class.new(record: plant, version_id: create_version.id).call

      expect(result.errors).to be_empty
      expect(plant.errors).not_to be_empty
    end
  end

  describe 'a variety restore' do
    let(:variety) { create(:variety, has_edible_mature_fruit: false) }

    it 'restores editable content attributes' do
      create_version = versions_for(variety).first
      variety.update!(has_edible_mature_fruit: true)

      described_class.new(record: variety, version_id: create_version.id).call

      expect(variety.reload.has_edible_mature_fruit).to be false
    end
  end
end
```
- [ ] Run `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/services/change_history/restorer_spec.rb`. Expect failure `NameError: uninitialized constant ChangeHistory::Restorer`.
- [ ] Create `app/services/change_history/restorer.rb`:
```ruby
# frozen_string_literal: true

module ChangeHistory
  # Restores a plant or variety to the state it had immediately AFTER a chosen
  # entry, by reifying the version that follows it in that record's chain (a
  # PaperTrail version stores the state BEFORE its own change).
  #
  # Only editable content attributes are applied: the set the Update mutations
  # accept, plus the whole Mobility container column. Ownership, visibility, the
  # publication trio, sync bookkeeping and timestamps are never written, so the
  # OrganizedResource dual-write invariant cannot be violated and the sync
  # machinery sees a restore as an ordinary edit. PaperTrail stays audit-only.
  #
  # Child rows (common names, relation links, images) are out of scope for v1.
  class Restorer
    Result = Struct.new(:record, :errors, keyword_init: true)

    ERROR_FIELD = 'versionId'

    PLANT_ATTRIBUTES = (
      %w[scientific_name family_names early_growth_phase life_cycle translations] +
      Mutations::Concerns::PlantEditableArguments::BOOLEAN_FIELDS.map(&:to_s) +
      Mutations::Concerns::RangeLiteralValidation::RANGE_FIELDS.map(&:to_s)
    ).freeze

    VARIETY_ATTRIBUTES = (
      %w[translations] +
      Mutations::Concerns::VarietyEditableArguments::BOOLEAN_FIELDS.map(&:to_s) +
      Mutations::Concerns::RangeLiteralValidation::RANGE_FIELDS.map(&:to_s)
    ).freeze

    RESTORABLE_ATTRIBUTES = {
      'Plant' => PLANT_ATTRIBUTES,
      'Variety' => VARIETY_ATTRIBUTES
    }.freeze

    def initialize(record:, version_id:)
      @record = record
      @version_id = version_id
      @item_type = record.class.base_class.name
    end

    def call
      guard = guard_error
      return Result.new(record: @record, errors: [guard]) if guard

      apply(restorable_attributes)
      Result.new(record: @record, errors: [])
    end

    private

    def guard_error
      return error(404, 'That change entry does not belong to this record.') if version.nil?

      if @record.respond_to?(:visibility_deleted?) && @record.visibility_deleted?
        return error(400, 'Restore this record from the trash before restoring an earlier change.')
      end

      return error(400, 'That change is already the current state of this record.') if successor.nil?
      return error(400, 'That change cannot be restored: its stored state is unreadable.') if reified.nil?

      nil
    end

    def version
      return @version if defined?(@version)

      @version = PaperTrail::Version.find_by(id: @version_id, item_type: @item_type, item_id: @record.id)
    end

    def successor
      return @successor if defined?(@successor)

      @successor = PaperTrail::Version
                   .where(item_type: @item_type, item_id: @record.id)
                   .where('versions.id > ?', version.id)
                   .order(:id)
                   .first
    end

    def reified
      return @reified if defined?(@reified)

      @reified = begin
        successor.reify
      rescue StandardError => e
        Rails.logger.warn("ChangeHistory::Restorer could not reify version #{successor.id}: #{e.class}")
        nil
      end
    end

    def restorable_attributes
      allowed = RESTORABLE_ATTRIBUTES.fetch(@item_type, [])
      reified.attributes.slice(*allowed)
    end

    # A normal validated save, so model validations and the sync machinery
    # behave exactly as they do for a hand-made edit. The restore's own version
    # is stamped with the entry it came from, without dropping the request's
    # provenance metadata.
    def apply(attributes)
      info = (PaperTrail.request.controller_info || {}).dup
      metadata = (info[:metadata] || info['metadata'] || {}).dup
      metadata[:restored_from_version_id] = version.id
      info.delete('metadata')
      info[:metadata] = metadata

      PaperTrail.request(controller_info: info) do
        @record.update(attributes)
      end
    end

    def error(code, message)
      { field: ERROR_FIELD, message: message, code: code }
    end
  end
end
```
- [ ] Run `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/services/change_history/restorer_spec.rb`. Expect `10 examples, 0 failures`.
- [ ] Run `docker compose run --rm web bundle exec rubocop`. Expect `no offenses detected`.
- [ ] Commit:
```bash
git add app/services/change_history/restorer.rb spec/services/change_history/restorer_spec.rb
git commit -m "Add the record history restore service" -m "Restoring an entry reifies the version that follows it and writes back only the editable content attributes plus the translations column, as an ordinary validated save. Ownership, visibility, the publication trio and sync bookkeeping are never touched, and the resulting version carries restored_from_version_id alongside the request provenance." -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: restorePlantVersion and restoreVarietyVersion mutations

**Files:**
- Create: `app/graphql/mutations/concerns/change_entry_argument.rb`
- Create: `app/graphql/mutations/restore_plant_version.rb`
- Create: `app/graphql/mutations/restore_variety_version.rb`
- Modify: `app/graphql/types/mutation_type.rb` (add two fields next to `field :restore_plant` / `field :restore_variety`, around lines 285-290)
- Modify: `schema.graphql` (regenerated)
- Test: `spec/mutations/restore_plant_version_spec.rb`
- Test: `spec/mutations/restore_variety_version_spec.rb`

**Interfaces:**
- Consumes: `ChangeHistory::Restorer` (Task 6), the `ChangeEntry` global id format from Task 5, `BaseMutation#errors_from_active_record`.
- Produces:
  - SDL: `restorePlantVersion(input: RestorePlantVersionInput!): RestorePlantVersionPayload` with input fields `plantId: ID!`, `versionId: ID!` and payload `{ plant: Plant, errors: [MutationError!]! }`.
  - SDL: `restoreVarietyVersion(input: RestoreVarietyVersionInput!): RestoreVarietyVersionPayload` with input fields `varietyId: ID!`, `versionId: ID!` and payload `{ variety: Variety, errors: [MutationError!]! }`.
  - `Mutations::Concerns::ChangeEntryArgument#decode_change_entry_id(global_id) -> Integer | nil` and `#change_entry_not_found_error -> Hash`.

**Steps:**

- [ ] Write the failing test at `spec/mutations/restore_plant_version_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RestorePlantVersion Mutation', type: :graphql_mutation do
  let(:mutation) do
    <<~GRAPHQL
      mutation($input: RestorePlantVersionInput!) {
        restorePlantVersion(input: $input) {
          plant { id scientificName }
          errors { field message code }
        }
      }
    GRAPHQL
  end

  def entry_id(version)
    GraphQL::Schema::UniqueWithinType.encode('ChangeEntry', version.id)
  end

  def execute(plant, user, version_id)
    PlantApiSchema.execute(
      mutation,
      context: { current_user: user },
      variables: {
        input: {
          plantId: PlantApiSchema.id_from_object(plant, Plant, {}),
          versionId: version_id
        }
      }
    )
  end

  def versions_for(plant)
    PaperTrail::Version.where(item_type: 'Plant', item_id: plant.id).order(:id)
  end

  describe 'authorization', versioning: true do
    let(:plant) { create(:plant, :public, scientific_name: 'Original') }

    it 'returns 401 for anonymous callers' do
      plant.update!(scientific_name: 'Second')
      result = execute(plant, nil, entry_id(versions_for(plant).first))

      expect(result.dig('errors', 0, 'extensions', 'code')).to eq 401
    end

    it 'returns 403 for a user who cannot edit' do
      plant.update!(scientific_name: 'Second')
      result = execute(plant, build(:user, :readonly), entry_id(versions_for(plant).first))

      expect(result.dig('errors', 0, 'extensions', 'code')).to eq 403
    end
  end

  describe 'restoring', versioning: true do
    let(:user) { build(:user, :readwrite) }
    let(:plant) do
      create(:plant, owned_by: user.email, created_by: user.email, scientific_name: 'Original')
    end

    it 'restores the record and reports no errors' do
      create_version = versions_for(plant).first
      plant.update!(scientific_name: 'Second')

      result = execute(plant, user, entry_id(create_version))
      payload = result.dig('data', 'restorePlantVersion')

      expect(result['errors']).to be_nil
      expect(payload['errors']).to be_empty
      expect(payload.dig('plant', 'scientificName')).to eq 'Original'
      expect(plant.reload.scientific_name).to eq 'Original'
    end

    it 'returns a payload error for the newest entry' do
      plant.update!(scientific_name: 'Second')
      payload = execute(plant, user, entry_id(versions_for(plant).last)).dig('data', 'restorePlantVersion')

      expect(payload['errors'].first['code']).to eq 400
      expect(payload['errors'].first['field']).to eq 'versionId'
    end

    it 'returns a payload error for a malformed entry id' do
      payload = execute(plant, user, 'not-a-global-id').dig('data', 'restorePlantVersion')

      expect(payload['errors'].first['code']).to eq 404
      expect(payload['errors'].first['field']).to eq 'versionId'
    end

    it 'returns a payload error for a global id of the wrong type' do
      wrong = PlantApiSchema.id_from_object(plant, Plant, {})
      payload = execute(plant, user, wrong).dig('data', 'restorePlantVersion')

      expect(payload['errors'].first['code']).to eq 404
    end
  end
end
```
- [ ] Run `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/mutations/restore_plant_version_spec.rb`. Expect all examples to fail with `No such type RestorePlantVersionInput`.
- [ ] Create `app/graphql/mutations/concerns/change_entry_argument.rb`:
```ruby
# frozen_string_literal: true

module Mutations
  module Concerns
    # Shared decoding for the opaque ChangeEntry global id the restore-version
    # mutations accept. A malformed id, an id of another type, or a non-numeric
    # payload all mean the same thing to a caller: no such entry.
    module ChangeEntryArgument
      TYPE_NAME = 'ChangeEntry'
      NOT_FOUND_ERROR = {
        field: 'versionId',
        message: 'Change entry not found.',
        code: 404
      }.freeze

      def decode_change_entry_id(global_id)
        type_name, raw_id = GraphQL::Schema::UniqueWithinType.decode(global_id)
        return nil unless type_name == TYPE_NAME

        Integer(raw_id, 10)
      rescue ArgumentError, TypeError, GraphQL::ExecutionError
        nil
      end

      def change_entry_not_found_error
        NOT_FOUND_ERROR
      end
    end
  end
end
```
- [ ] Create `app/graphql/mutations/restore_plant_version.rb`:
```ruby
# frozen_string_literal: true

module Mutations
  # Restores a plant to the state it had immediately after a chosen history
  # entry. Gated by the same update? policy that gates editing and reading the
  # history itself.
  class RestorePlantVersion < BaseMutation
    include Mutations::Concerns::ChangeEntryArgument

    argument :plant_id, ID, required: true, loads: Types::PlantType
    argument :version_id, ID, required: true,
                              description: 'The id of the ChangeEntry to restore, from recordHistory.'

    field :plant, Types::PlantType, null: true
    field :errors, [Types::MutationError], null: false

    def authorized?(plant:, **_attributes)
      authorize plant, :update?
      true
    end

    def resolve(plant:, version_id:)
      decoded = decode_change_entry_id(version_id)
      return { plant: plant, errors: [change_entry_not_found_error] } if decoded.nil?

      result = ChangeHistory::Restorer.new(record: plant, version_id: decoded).call
      return { plant: plant, errors: result.errors } if result.errors.any?

      { plant: plant, errors: errors_from_active_record(plant.errors) }
    end
  end
end
```
- [ ] Create `app/graphql/mutations/restore_variety_version.rb` as the same class with `Variety` substituted throughout (`class RestoreVarietyVersion`, `argument :variety_id, ID, required: true, loads: Types::VarietyType`, `field :variety, Types::VarietyType, null: true`, `def authorized?(variety:, **_attributes)`, `def resolve(variety:, version_id:)`, and `{ variety: variety, ... }` payloads).
- [ ] Modify `app/graphql/types/mutation_type.rb`: add these two fields immediately after the `field :restore_variety, ...` block (around line 290):
```ruby
    field :restore_plant_version,
          mutation: Mutations::RestorePlantVersion,
          description: 'Restores a plant to the state it had immediately after a chosen record history entry'
    field :restore_variety_version,
          mutation: Mutations::RestoreVarietyVersion,
          description: 'Restores a variety to the state it had immediately after a chosen record history entry'
```
- [ ] Run `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/mutations/restore_plant_version_spec.rb`. Expect `6 examples, 0 failures`.
- [ ] Write `spec/mutations/restore_variety_version_spec.rb` as the variety mirror of the plant spec: same structure, `$input: RestoreVarietyVersionInput!`, `restoreVarietyVersion`, `variety { id hasEdibleMatureFruit }`, `varietyId`, `PaperTrail::Version.where(item_type: 'Variety', ...)`, a variety created with `create(:variety, owned_by: user.email, created_by: user.email, has_edible_mature_fruit: false)` and updated with `variety.update!(has_edible_mature_fruit: true)`; keep the anonymous 401, read-only 403, happy-path restore and newest-entry 400 examples.
- [ ] Run `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/mutations/restore_variety_version_spec.rb`. Expect `4 examples, 0 failures`.
- [ ] Regenerate the SDL: `docker compose run --rm -e RAILS_ENV=test web bundle exec rails graphql:schema:dump`. Expect additions only: `RestorePlantVersionInput`, `RestorePlantVersionPayload`, `RestoreVarietyVersionInput`, `RestoreVarietyVersionPayload` and the two mutation fields.
- [ ] Run `docker compose run --rm web bundle exec rubocop`. Expect `no offenses detected`.
- [ ] Commit:
```bash
git add app/graphql/mutations/concerns/change_entry_argument.rb app/graphql/mutations/restore_plant_version.rb app/graphql/mutations/restore_variety_version.rb app/graphql/types/mutation_type.rb schema.graphql spec/mutations/restore_plant_version_spec.rb spec/mutations/restore_variety_version_spec.rb
git commit -m "Add restorePlantVersion and restoreVarietyVersion" -m "Both follow the standard mutation shape: Pundit update? in authorized?, a { record, errors } payload, and payload errors for an unknown entry, an entry belonging to another record, the newest entry and a soft-deleted record." -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: End-to-end flow spec and final gates

**Files:**
- Create: `spec/requests/record_history_flow_spec.rb`
- Test: itself, plus the whole suite

**Interfaces:**
- Consumes: everything from Tasks 1 to 7. Adds no production code.
- Produces: a single spec that exercises edit, then history with actor and diff, then restore, then the new `RESTORED` entry.

**Steps:**

- [ ] Write the failing test at `spec/requests/record_history_flow_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

# The whole feature end to end at the schema boundary: edit a plant, read the
# history it produced, restore an earlier entry, and see the restore recorded.
RSpec.describe 'Record history end to end', type: :request do
  let(:user) { build(:user, :readwrite) }
  let(:plant) do
    create(:plant, owned_by: user.email, created_by: user.email, scientific_name: 'Original Name')
  end

  let(:history_query) do
    <<~GRAPHQL
      query($id: ID!) {
        plant(id: $id) {
          recordHistory(first: 10) {
            totalCount
            edges { node { id event origin actorLabel subjectType restorable changes { field before after } } }
          }
        }
      }
    GRAPHQL
  end

  let(:restore_mutation) do
    <<~GRAPHQL
      mutation($input: RestorePlantVersionInput!) {
        restorePlantVersion(input: $input) {
          plant { scientificName }
          errors { field message code }
        }
      }
    GRAPHQL
  end

  def plant_global_id
    PlantApiSchema.id_from_object(plant, Plant, {})
  end

  def history_nodes
    PlantApiSchema
      .execute(history_query, context: { current_user: user }, variables: { id: plant_global_id })
      .dig('data', 'plant', 'recordHistory', 'edges')
      .map { |edge| edge['node'] }
  end

  it 'shows the edit, restores it, and records the restore', versioning: true do
    PaperTrail.request(
      whodunnit: user.principal.id,
      controller_info: { metadata: { origin: 'api', principal_id: user.principal.id } }
    ) do
      plant.update!(scientific_name: 'Edited Name')
    end

    nodes = history_nodes
    expect(nodes.first['event']).to eq 'UPDATED'
    # The :user factory resolves a principal without a display name.
    expect(nodes.first['actorLabel']).to eq user.email
    expect(nodes.first['changes']).to include(
      'field' => 'scientificName', 'before' => 'Original Name', 'after' => 'Edited Name'
    )

    restorable = nodes.find { |node| node['restorable'] }
    expect(restorable['event']).to eq 'CREATED'

    payload = PlantApiSchema.execute(
      restore_mutation,
      context: { current_user: user },
      variables: { input: { plantId: plant_global_id, versionId: restorable['id'] } }
    ).dig('data', 'restorePlantVersion')

    expect(payload['errors']).to be_empty
    expect(payload.dig('plant', 'scientificName')).to eq 'Original Name'
    expect(plant.reload.scientific_name).to eq 'Original Name'

    after_restore = history_nodes
    expect(after_restore.first['event']).to eq 'RESTORED'
    expect(after_restore.first['subjectType']).to eq 'RECORD'
    expect(after_restore.first['changes']).to include(
      'field' => 'scientificName', 'before' => 'Edited Name', 'after' => 'Original Name'
    )
  end
end
```
- [ ] Run `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/requests/record_history_flow_spec.rb`. Expect it to pass on the first run because every piece already exists; if it fails, fix the production code (not the spec) before continuing.
- [ ] Confirm the mobile contract is untouched: `git diff --stat origin/main -- spec/contracts` must print nothing, and `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/contracts` must report 0 failures.
- [ ] Run the full suite: `docker compose run --rm -e RAILS_ENV=test web bundle exec rspec`. Expect 0 failures and roughly 1943 + 46 examples.
- [ ] Run `docker compose run --rm web bundle exec rubocop`. Expect `no offenses detected`.
- [ ] Verify the schema drift gate is clean: `docker compose run --rm -e RAILS_ENV=test web bundle exec rails graphql:schema:dump && git diff --exit-code schema.graphql`. Expect exit status 0 and no output.
- [ ] Verify nothing untracked crept in: `git status --short` must show only `?? docker-compose.override.yml`.
- [ ] Commit:
```bash
git add spec/requests/record_history_flow_spec.rb
git commit -m "Add an end to end record history and restore spec" -m "Edit a plant, read the entry with its actor and diff, restore the creation entry, and assert the restore itself lands in the timeline as a RESTORED entry." -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Spec coverage map

| Design spec requirement | Task |
| --- | --- |
| GIN index on `versions.metadata` (`jsonb_path_ops`, concurrently) | 1 |
| Child stamping concern on common names, 7 join models, images | 2 |
| `metadata @>` root query, newest first, paginated | 3 |
| Actor resolution order with batching | 3 |
| Diff builder: camelCase names, per-locale translations, noise skipping, humanized values | 4 |
| Join create/destroy rendered as added/removed with looked-up name and graceful fallback | 4 (Subject) + 5 (event mapping) |
| Visibility and ownership changes shown but non-restorable | 4 (kept in diff) + 5 (`restorable` is RECORD-only and never for the newest entry) |
| `ChangeEntryType` + connection, enums, `NODE_FORBIDDEN_TYPES`, opaque id | 5 |
| `recordHistory` on `PlantType`/`VarietyType`, `update?` gated, `totalCount` | 5 |
| Restore semantics: state after V, already-current 400, deleted 400, whitelist, validated save, `restored_from_version_id` | 6 |
| `restorePlantVersion` / `restoreVarietyVersion` | 7 |
| Sync record behaves as an ordinary edit (PaperTrail stays audit-only) | 6 (whitelist excludes every sync column; asserted by the "never touches ownership, visibility or sync columns" example) |
| Full suite + RuboCop + end-to-end request spec | 8 |
