# Draft and Publish (API) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an editor stage changes to a published record so the current version stays live until they publish, instead of the record disappearing the moment anything is unfinished.

**Architecture:** The live row is never touched by editing. A polymorphic `record_drafts` row holds the working copy; publishing replays it through the normal update path. Reads gain a `perspective` lens (`PUBLISHED | DRAFT`, default `PUBLISHED`) that applies the draft in memory without saving, so anonymous and mobile callers structurally cannot receive draft content. Conflict detection uses the existing PaperTrail audit trail — which this design deliberately does *not* use for storage.

**Tech Stack:** Rails 8.1.3, Ruby 3.4.10, PostgreSQL (uuid PKs via pgcrypto), graphql-ruby, Pundit, Mobility (container backend), PaperTrail 17, RSpec + FactoryBot.

**Design spec:** `docs/superpowers/specs/2026-08-07-draft-publish-design.md` (PR #108). Read it before starting — it records why PaperTrail is not the storage mechanism and why several obvious alternatives were rejected.

## Corrections applied during execution

This plan (and the design spec above) contained a few inaccuracies caught in
the final whole-branch review and corrected in the shipped code and docs, not
in this plan text. When reading either document, keep these in mind:

- **Conflict detection is strictly-greater-than, not inclusive.** The range
  test is `created_at > draft.base_updated_at`; the version at exactly the
  boundary IS the base state the draft was staged against, not a conflict.
- **Publish does not "replay through the normal update path."** The shipped
  `Drafts::Publisher` assigns the draft's staged values onto the loaded record
  in memory via `Drafts::Overlay`, then explicitly applies the family-name
  mirror and the publication-state flip itself, then saves once. There is no
  mutation-layer replay.
- **User specs use factory traits, not `trust_level:`.** `build(:user,
  trust_level: 10)` is a dead parameter -- the factory only takes trust levels
  via traits (`build(:user, :superadmin)`, `:admin`, `:readwrite`,
  `:readonly`).
- **The empty-translations savability guard lives in `Drafts::Overlay`**
  (`keep_container_savable`), not in the publisher or the mutation layer.

For the full history of how these were found and fixed, see the `.superpowers`
ledger history in git rather than treating this plan as current truth on these
points.

## Global Constraints

- **The frozen mobile contract must not change.** `spec/contracts/mobile_*` passing untouched is the regression proof for this whole plan. Never modify those files.
- **`ECHO_Plant_API` is a PUBLIC repo.** Never commit real emails, uids, or org names — in code, specs, fixtures, or comments. Use `example.com` addresses.
- **ASCII only in code comments.** RuboCop enforces it. No em dashes, no smart quotes.
- **Default perspective is `PUBLISHED`.** Any code path that can return draft content must require an explicit argument AND `authorize record, :update?`.
- **The permitted-key whitelist derives from the same constants `ChangeHistory::Restorer` uses.** Two whitelists that can drift is the bug this plan must not create.
- **`RecordDraft` must opt out of PaperTrail.** `ApplicationRecord` calls `has_paper_trail` unconditionally; without an opt-out every draft save writes an audit version. This fails silently, so it gets its own test.
- **Run tests with the test env forced:** `docker compose run -e RAILS_ENV=test web bundle exec rspec`. The `.env` must stay `RAILS_ENV=development` for the dev server.
- Branch: `feat/draft-publish`.

---

## Pre-existing bug this plan must not inherit

`ChangeHistory::Restorer::PLANT_ATTRIBUTES` is:

```ruby
%w[scientific_name family_names early_growth_phase life_cycle translations] +
  Mutations::Concerns::PlantEditableArguments::BOOLEAN_FIELDS.map(&:to_s) +
  Mutations::Concerns::RangeLiteralValidation::RANGE_FIELDS.map(&:to_s)
```

**`family_id` is missing.** Botanical families landed after record-history, and the whitelist was never extended. So `plants.family_id` changes are versioned by PaperTrail and shown in the history drawer, but "restore this version" silently does not revert the family assignment — the same silent-skip class as the empty-translations issue already documented in `Restorer`.

Task 2 fixes this by extracting one shared constant that both `Restorer` and `RecordDraft` consume. That is a behaviour change to restore, and it is deliberate: it is a bug fix, and it needs its own test and its own line in the PR description.

---

## File Structure

**Create:**

| File | Responsibility |
| --- | --- |
| `db/migrate/<ts>_create_record_drafts.rb` | The table |
| `app/models/record_draft.rb` | The draft row; PaperTrail opt-out lives here |
| `app/models/concerns/draftable.rb` | `has_one :record_draft`; included by the four draftable models |
| `app/models/concerns/draftable_attributes.rb` | The single source of the permitted-key whitelist, per model |
| `app/services/drafts/overlay.rb` | Applies a draft onto a record in memory, never saving |
| `app/services/drafts/conflict_detector.rb` | "Did live move under this draft?", via PaperTrail |
| `app/services/drafts/publisher.rb` | The locked publish transaction |
| `app/graphql/types/record_draft_info_type.rb` | Draft metadata exposed on the four types |
| `app/graphql/types/perspective_enum.rb` | `PUBLISHED \| DRAFT` |
| `app/graphql/mutations/publish_draft.rb` | |
| `app/graphql/mutations/discard_draft.rb` | |
| `app/graphql/types/concerns/draft_fields.rb` | The `draft` field, included by the four types |
| Specs for each of the above | |

**Modify:**

| File | Change |
| --- | --- |
| `app/models/{plant,variety,family,category}.rb` | `include Draftable` |
| `app/services/change_history/restorer.rb` | Consume the shared whitelist constant (fixes the `family_id` gap) |
| `app/graphql/mutations/{update_plant,update_variety,update_family,update_category}.rb` | `saveAsDraft` argument |
| `app/graphql/types/query_type.rb` | `perspective` argument on the four single-record queries |
| `app/graphql/types/{plant,variety,family,category}_type.rb` | `include Types::Concerns::DraftFields` |
| `app/graphql/mutation_type.rb` | Register the two new mutations |
| `app/graphql/resolvers/{plants,varieties,families,categories}_resolver.rb` | `has_pending_changes` filter |

---

### Task 1: The record_drafts table and model

**Files:**
- Create: `db/migrate/<timestamp>_create_record_drafts.rb`
- Create: `app/models/record_draft.rb`
- Create: `spec/models/record_draft_spec.rb`
- Create: `spec/factories/record_drafts.rb`

**Interfaces:**
- Produces: `RecordDraft` with `draftable` (polymorphic), `data` (jsonb), `base_updated_at`, `author_principal_id`, `last_editor_principal_id`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/models/record_draft_spec.rb
require 'rails_helper'

RSpec.describe RecordDraft do
  let(:plant) { create(:plant) }

  # This is the whole reason drafts are not stored in PaperTrail. If a draft
  # save writes a version, the recordHistory drawer fills with edits that never
  # happened to the live record. ApplicationRecord calls has_paper_trail
  # unconditionally, so the opt-out is easy to lose in a refactor and silent
  # when lost.
  it 'writes no PaperTrail versions' do
    expect {
      draft = described_class.create!(draftable: plant, data: { 'scientific_name' => 'X' },
                                      base_updated_at: plant.updated_at)
      draft.update!(data: { 'scientific_name' => 'Y' })
      draft.destroy!
    }.not_to change { PaperTrail::Version.where(item_type: 'RecordDraft').count }.from(0)
  end

  it 'allows only one draft per record' do
    described_class.create!(draftable: plant, data: {}, base_updated_at: plant.updated_at)
    expect {
      described_class.create!(draftable: plant, data: {}, base_updated_at: plant.updated_at)
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'allows drafts on different records of the same type' do
    other = create(:plant)
    described_class.create!(draftable: plant, data: {}, base_updated_at: plant.updated_at)
    expect {
      described_class.create!(draftable: other, data: {}, base_updated_at: other.updated_at)
    }.not_to raise_error
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `docker compose run -e RAILS_ENV=test web bundle exec rspec spec/models/record_draft_spec.rb`
Expected: FAIL, `uninitialized constant RecordDraft`

- [ ] **Step 3: Write the migration**

```ruby
# db/migrate/<timestamp>_create_record_drafts.rb
class CreateRecordDrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :record_drafts, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :draftable_type, null: false
      t.uuid   :draftable_id,   null: false

      # Changed keys only, using model attribute names. `translations` is one
      # key holding the whole Mobility container blob.
      t.jsonb  :data, null: false, default: {}

      # The live row's updated_at when this draft was CREATED. Never advanced by
      # subsequent draft saves: if it were, a conflict arriving mid-draft would
      # be silently swallowed.
      t.datetime :base_updated_at, null: false

      t.uuid :author_principal_id,      null: false
      t.uuid :last_editor_principal_id, null: false

      t.timestamps
    end

    # One draft per record, enforced by the database rather than by convention.
    add_index :record_drafts, %i[draftable_type draftable_id], unique: true,
              name: 'index_record_drafts_on_draftable'
    add_foreign_key :record_drafts, :principals, column: :author_principal_id
    add_foreign_key :record_drafts, :principals, column: :last_editor_principal_id
  end
end
```

- [ ] **Step 4: Write the model**

```ruby
# app/models/record_draft.rb
# frozen_string_literal: true

# A working copy of a record's own columns, held off the live row so an
# unfinished edit does not force the record out of public view.
#
# Deliberately NOT versioned. ApplicationRecord calls has_paper_trail on every
# model; drafts must opt out, because a draft save is not something that
# happened to the live record. Storing drafts IN PaperTrail was considered and
# rejected -- see docs/superpowers/specs/2026-08-07-draft-publish-design.md.
class RecordDraft < ApplicationRecord
  # Disables the inherited has_paper_trail for this model only. Covered by
  # spec/models/record_draft_spec.rb, because the failure mode is silent.
  self.paper_trail.disable if respond_to?(:paper_trail)

  belongs_to :draftable, polymorphic: true

  belongs_to :author, class_name: 'Principal', foreign_key: :author_principal_id, inverse_of: false
  belongs_to :last_editor, class_name: 'Principal', foreign_key: :last_editor_principal_id,
             inverse_of: false

  validates :base_updated_at, presence: true

  # The attribute names this draft changes. Drives the changed-field markers,
  # the history-drawer entry, and conflict detection.
  def changed_fields
    data.keys
  end
end
```

If `self.paper_trail.disable` is not the correct PaperTrail 17 API for a model-level opt-out, use `has_paper_trail on: []` instead. Verify against the installed gem before choosing; the spec in Step 1 is the arbiter.

- [ ] **Step 5: Write the factory**

```ruby
# spec/factories/record_drafts.rb
FactoryBot.define do
  factory :record_draft do
    association :draftable, factory: :plant
    data { {} }
    base_updated_at { Time.current }
    author_principal_id { create(:principal).id }
    last_editor_principal_id { author_principal_id }
  end
end
```

- [ ] **Step 6: Migrate and run the spec**

Run: `docker compose run -e RAILS_ENV=test web bundle exec rails db:migrate && docker compose run -e RAILS_ENV=test web bundle exec rspec spec/models/record_draft_spec.rb`
Expected: PASS, 3 examples

- [ ] **Step 7: Commit**

```bash
git add db/migrate db/structure.sql app/models/record_draft.rb spec/models/record_draft_spec.rb spec/factories/record_drafts.rb
git commit -m "feat(drafts): record_drafts table and model, deliberately unversioned"
```

---

### Task 2: Draftable concern and the single-source whitelist

This is where the `family_id` restore bug gets fixed. One constant per model, consumed by both `RecordDraft` and `ChangeHistory::Restorer`, so they cannot drift.

**Files:**
- Create: `app/models/concerns/draftable_attributes.rb`
- Create: `app/models/concerns/draftable.rb`
- Modify: `app/models/plant.rb`, `variety.rb`, `family.rb`, `category.rb`
- Modify: `app/services/change_history/restorer.rb`
- Create: `spec/models/concerns/draftable_attributes_spec.rb`
- Modify: `spec/services/change_history/restorer_spec.rb`

**Interfaces:**
- Produces: `DraftableAttributes.for(model_class) -> Array<String>`; `Draftable` giving `record.record_draft`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/models/concerns/draftable_attributes_spec.rb
require 'rails_helper'

RSpec.describe DraftableAttributes do
  it 'includes family_id for Plant' do
    # Regression: families landed after record-history and the restore
    # whitelist was never extended, so restoring a version silently left the
    # family assignment untouched. One shared constant prevents a repeat.
    expect(described_class.for(Plant)).to include('family_id')
  end

  it 'includes translations for every draftable model' do
    [Plant, Variety, Family, Category].each do |model|
      expect(described_class.for(model)).to include('translations')
    end
  end

  it 'never includes ownership or workflow columns' do
    forbidden = %w[id visibility publication_state access_level deleted_at owned_by created_by
                   owner_organization_id created_by_principal_id]
    [Plant, Variety, Family, Category].each do |model|
      expect(described_class.for(model) & forbidden).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `docker compose run -e RAILS_ENV=test web bundle exec rspec spec/models/concerns/draftable_attributes_spec.rb`
Expected: FAIL, `uninitialized constant DraftableAttributes`

- [ ] **Step 3: Write the whitelist**

```ruby
# app/models/concerns/draftable_attributes.rb
# frozen_string_literal: true

# The single source of truth for which columns may be staged in a draft and
# restored from a version.
#
# ChangeHistory::Restorer and RecordDraft both consume this. They used to carry
# separate lists, and the copies drifted: family_id was added to plants when
# botanical families landed, and the restore whitelist was never extended, so
# restoring a version silently left the family assignment untouched.
#
# Deliberately excludes every ownership, provenance and workflow column.
# Visibility is changed through its own mutation arguments and is never staged:
# publishing a draft is what changes publication state.
module DraftableAttributes
  module_function

  PLANT = (
    %w[scientific_name family_names family_id early_growth_phase life_cycle translations] +
    Mutations::Concerns::PlantEditableArguments::BOOLEAN_FIELDS.map(&:to_s) +
    Mutations::Concerns::RangeLiteralValidation::RANGE_FIELDS.map(&:to_s)
  ).freeze

  VARIETY = (
    %w[translations] +
    Mutations::Concerns::VarietyEditableArguments::BOOLEAN_FIELDS.map(&:to_s) +
    Mutations::Concerns::RangeLiteralValidation::RANGE_FIELDS.map(&:to_s)
  ).freeze

  FAMILY = %w[translations storage_physiology seed_longevity seed_banking_rank].freeze

  CATEGORY = %w[translations].freeze

  BY_MODEL = {
    'Plant' => PLANT, 'Variety' => VARIETY, 'Family' => FAMILY, 'Category' => CATEGORY
  }.freeze

  def for(model_class)
    BY_MODEL.fetch(model_class.name)
  end
end
```

- [ ] **Step 4: Write the Draftable concern**

```ruby
# app/models/concerns/draftable.rb
# frozen_string_literal: true

# Gives a model its optional working copy. Included by the four models that
# have translatable fields and an editing surface worth staging.
module Draftable
  extend ActiveSupport::Concern

  included do
    has_one :record_draft, as: :draftable, dependent: :destroy
  end

  # True when a published version exists AND there are staged changes. Drives
  # the "Published - edited" status. Derived, never stored: Wagtail keeps a
  # has_unpublished_changes column, and a stored flag is one more thing that can
  # drift from reality.
  def pending_changes?
    record_draft.present?
  end

  def draftable_attribute_names
    DraftableAttributes.for(self.class)
  end
end
```

- [ ] **Step 5: Include it in the four models**

Add `include Draftable` beside the existing `include OrganizedResource` in `app/models/plant.rb`, `variety.rb`, and `category.rb`. In `app/models/family.rb` add it after the `extend Mobility` line — Family is a pure lookup and does not include `OrganizedResource`.

- [ ] **Step 6: Point Restorer at the shared constant**

In `app/services/change_history/restorer.rb`, replace the two literal arrays:

```ruby
    PLANT_ATTRIBUTES = DraftableAttributes::PLANT
    VARIETY_ATTRIBUTES = DraftableAttributes::VARIETY
```

- [ ] **Step 7: Add the restore regression spec**

Append to `spec/services/change_history/restorer_spec.rb`:

```ruby
  it 'restores a changed family assignment' do
    old_family = create(:family)
    new_family = create(:family)
    plant = create(:plant, family: old_family)
    plant.update!(family: new_family)

    version = plant.versions.last
    described_class.new(record: plant, version_id: version.id).call

    expect(plant.reload.family_id).to eq(old_family.id)
  end
```

Match the existing spec file's construction of `Restorer` — read it first; the constructor signature above is illustrative and must be corrected to the real one.

- [ ] **Step 8: Run the specs**

Run: `docker compose run -e RAILS_ENV=test web bundle exec rspec spec/models/concerns/draftable_attributes_spec.rb spec/services/change_history/restorer_spec.rb`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add app/models app/services/change_history/restorer.rb spec
git commit -m "fix(history): restore family assignments, via one shared draftable whitelist"
```

---

### Task 3: The overlay service

Applies a draft onto a loaded record in memory and never saves. Same shape as `ChangeHistory::Restorer` reifying a version, different source.

**Files:**
- Create: `app/services/drafts/overlay.rb`
- Create: `spec/services/drafts/overlay_spec.rb`

**Interfaces:**
- Produces: `Drafts::Overlay.apply(record, draft) -> record` (the same instance, attributes assigned, unsaved)

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/services/drafts/overlay_spec.rb
require 'rails_helper'

RSpec.describe Drafts::Overlay do
  let(:plant) { create(:plant, scientific_name: 'Live name') }

  it 'applies staged values without saving' do
    draft = create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Draft name' })

    result = described_class.apply(plant, draft)

    expect(result.scientific_name).to eq('Draft name')
    expect(result).to be_changed
    expect(plant.reload.scientific_name).to eq('Live name')
  end

  it 'ignores keys outside the whitelist' do
    draft = create(:record_draft, draftable: plant,
                                  data: { 'visibility' => 1, 'owned_by' => 'x@example.com' })
    before_visibility = plant.visibility

    described_class.apply(plant, draft)

    expect(plant.visibility).to eq(before_visibility)
  end

  it 'returns the record untouched when there is no draft' do
    expect(described_class.apply(plant, nil).scientific_name).to eq('Live name')
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `docker compose run -e RAILS_ENV=test web bundle exec rspec spec/services/drafts/overlay_spec.rb`
Expected: FAIL, `uninitialized constant Drafts`

- [ ] **Step 3: Write the service**

```ruby
# app/services/drafts/overlay.rb
# frozen_string_literal: true

module Drafts
  # Applies a draft's staged values onto a loaded record IN MEMORY. The record
  # is never saved: the caller hands the dirty instance straight to graphql-ruby
  # for serialization, exactly as ChangeHistory::Restorer hands back a reified
  # version.
  #
  # The whitelist is re-applied here even though the write path already filters,
  # so a draft row written by an older version of the code (or by hand) cannot
  # overlay a column it was never allowed to stage.
  module Overlay
    module_function

    def apply(record, draft)
      return record if draft.nil?

      permitted = DraftableAttributes.for(record.class)
      draft.data.slice(*permitted).each do |attribute, value|
        record.public_send("#{attribute}=", value)
      end
      record
    end
  end
end
```

- [ ] **Step 4: Run the spec**

Run: `docker compose run -e RAILS_ENV=test web bundle exec rspec spec/services/drafts/overlay_spec.rb`
Expected: PASS, 3 examples

If assigning `translations` directly does not round-trip through the Mobility container backend, add a branch that merges the staged hash into `record.translations` rather than replacing the attribute wholesale, and add a spec asserting a staged Swahili description is visible under `Mobility.with_locale(:sw)` while the English stays live. Do not skip this: translations are the originating use case for the whole feature.

- [ ] **Step 5: Commit**

```bash
git add app/services/drafts spec/services/drafts
git commit -m "feat(drafts): in-memory overlay of a draft onto a loaded record"
```

---

### Task 4: saveAsDraft on the four update mutations

**Files:**
- Modify: `app/graphql/mutations/update_plant.rb`, `update_variety.rb`, `update_family.rb`, `update_category.rb`
- Create: `app/graphql/mutations/concerns/draft_writing.rb`
- Create: `spec/graphql/mutations/draft_writing_spec.rb`

**Interfaces:**
- Consumes: `DraftableAttributes` (Task 2)
- Produces: `saveAsDraft: Boolean` on the four mutations; `Mutations::Concerns::DraftWriting#write_draft(record, attributes)`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/graphql/mutations/draft_writing_spec.rb
require 'rails_helper'

RSpec.describe 'updatePlant saveAsDraft' do
  let(:user) { build(:user, trust_level: 10) }
  let(:plant) { create(:plant, scientific_name: 'Live name') }
  let(:mutation) do
    <<~GRAPHQL
      mutation($input: UpdatePlantInput!) {
        updatePlant(input: $input) {
          plant { id scientificName }
          errors { code field message }
        }
      }
    GRAPHQL
  end

  def execute(input)
    PlantApiSchema.execute(mutation, context: { current_user: user },
                                     variables: { input: input })
  end

  it 'leaves the live row untouched' do
    execute({ plantId: plant.to_global_id_param, scientificName: 'Draft name', saveAsDraft: true })
    expect(plant.reload.scientific_name).to eq('Live name')
  end

  it 'stores the change in a draft' do
    execute({ plantId: plant.to_global_id_param, scientificName: 'Draft name', saveAsDraft: true })
    expect(plant.reload.record_draft.data).to include('scientific_name' => 'Draft name')
  end

  it 'writes no PaperTrail version for the plant' do
    expect {
      execute({ plantId: plant.to_global_id_param, scientificName: 'Draft name', saveAsDraft: true })
    }.not_to(change { plant.versions.count })
  end

  it 'still writes live when saveAsDraft is absent, so mobile is unaffected' do
    execute({ plantId: plant.to_global_id_param, scientificName: 'Direct name' })
    expect(plant.reload.scientific_name).to eq('Direct name')
    expect(plant.record_draft).to be_nil
  end

  it 'merges successive draft saves rather than replacing them' do
    execute({ plantId: plant.to_global_id_param, scientificName: 'First', saveAsDraft: true })
    execute({ plantId: plant.to_global_id_param, familyNames: 'Testaceae', saveAsDraft: true })
    data = plant.reload.record_draft.data
    expect(data).to include('scientific_name' => 'First', 'family_names' => 'Testaceae')
  end

  it 'does not advance base_updated_at on a later save' do
    execute({ plantId: plant.to_global_id_param, scientificName: 'First', saveAsDraft: true })
    original = plant.reload.record_draft.base_updated_at
    execute({ plantId: plant.to_global_id_param, scientificName: 'Second', saveAsDraft: true })
    expect(plant.reload.record_draft.base_updated_at).to eq(original)
  end
end
```

Read `spec/factories/users.rb` first: `User` is an in-memory non-persisted model built from a JWT payload, so the `build(:user, trust_level: 10)` call above must match the real factory's attribute names.

- [ ] **Step 2: Run it to verify it fails**

Run: `docker compose run -e RAILS_ENV=test web bundle exec rspec spec/graphql/mutations/draft_writing_spec.rb`
Expected: FAIL, `saveAsDraft` is not a valid argument

- [ ] **Step 3: Write the concern**

```ruby
# app/graphql/mutations/concerns/draft_writing.rb
# frozen_string_literal: true

module Mutations
  module Concerns
    # Adds the saveAsDraft argument and the write path behind it.
    #
    # The API deliberately keeps the ability to write live directly:
    # SourceSynchronizer, the importers and the mobile app all need it. "Live is
    # only touched by Publish" is an editing-UI policy, not an API restriction.
    module DraftWriting
      def self.included(base)
        base.argument :save_as_draft, Boolean,
                      required: false,
                      default_value: false,
                      description: 'Stage these changes on a draft instead of writing the live record.'
      end

      # Merges the supplied attributes into the record's draft, creating it on
      # first use. Returns the draft.
      #
      # base_updated_at is set ONLY at creation. Advancing it on every save
      # would silently swallow a conflict that arrived mid-draft.
      def write_draft(record, attributes, language: nil)
        permitted = DraftableAttributes.for(record.class)
        incoming = stageable_data(record, attributes, permitted, language)

        draft = record.record_draft
        principal_id = context[:current_user]&.principal&.id

        if draft
          draft.update!(data: draft.data.merge(incoming), last_editor_principal_id: principal_id)
        else
          draft = RecordDraft.create!(
            draftable: record,
            data: incoming,
            base_updated_at: record.updated_at,
            author_principal_id: principal_id,
            last_editor_principal_id: principal_id
          )
        end
        draft
      end

      private

      # Translatable fields have to be staged as a container blob keyed by
      # locale, not as bare scalars, or a staged Swahili description would
      # overwrite the English on publish. Building the blob against the record's
      # CURRENT translations keeps every other locale intact.
      def stageable_data(record, attributes, permitted, language)
        scalars = attributes.stringify_keys.slice(*permitted)
        translatable = record.class.mobility_attributes.map(&:to_s)
        staged_translations = attributes.stringify_keys.slice(*translatable)
        return scalars if staged_translations.empty?

        locale = (language || Mobility.locale).to_s
        blob = (record.record_draft&.data&.dig('translations') || record.translations || {}).deep_dup
        blob[locale] = (blob[locale] || {}).merge(staged_translations)
        scalars.merge('translations' => blob)
      end
    end
  end
end
```

Verify `record.class.mobility_attributes` is the correct Mobility 1.x API for listing translated attribute names before relying on it; if not, derive the list from the `TRANSLATABLE_FIELDS` constants in the `*EditableArguments` concerns instead.

- [ ] **Step 4: Wire it into the four mutations**

In each of `update_plant.rb`, `update_variety.rb`, `update_family.rb`, `update_category.rb`: add `include Mutations::Concerns::DraftWriting`, and open `resolve` with:

```ruby
      if attributes.delete(:save_as_draft)
        draft = write_draft(plant, attributes, language: attributes[:language])
        return { plant: plant, errors: [] } if draft.persisted?
      end
```

substituting the right local and payload key per mutation. The record returned is the untouched live row; the client re-reads with `perspective: DRAFT` (Task 5) to see the staged values.

- [ ] **Step 5: Run the spec**

Run: `docker compose run -e RAILS_ENV=test web bundle exec rspec spec/graphql/mutations/draft_writing_spec.rb`
Expected: PASS, 6 examples

- [ ] **Step 6: Run the mobile contract as the regression proof**

Run: `docker compose run -e RAILS_ENV=test web bundle exec rspec spec/contracts/`
Expected: PASS, unchanged

- [ ] **Step 7: Commit**

```bash
git add app/graphql/mutations spec/graphql/mutations/draft_writing_spec.rb
git commit -m "feat(drafts): saveAsDraft on the four update mutations"
```

---

### Task 5: The perspective lens and the draft metadata field

**Files:**
- Create: `app/graphql/types/perspective_enum.rb`
- Create: `app/graphql/types/record_draft_info_type.rb`
- Create: `app/graphql/types/concerns/draft_fields.rb`
- Modify: `app/graphql/types/query_type.rb`
- Modify: `app/graphql/types/{plant,variety,family,category}_type.rb`
- Create: `spec/graphql/perspective_spec.rb`

**Interfaces:**
- Consumes: `Drafts::Overlay` (Task 3)
- Produces: `perspective` argument; `draft: RecordDraftInfoType`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/graphql/perspective_spec.rb
require 'rails_helper'

RSpec.describe 'perspective lens' do
  let(:plant) { create(:plant, scientific_name: 'Live name', visibility: :public) }
  let!(:draft) do
    create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Draft name' })
  end
  let(:query) do
    <<~GRAPHQL
      query($id: ID!, $perspective: Perspective) {
        plant(id: $id, perspective: $perspective) { scientificName }
      }
    GRAPHQL
  end

  def run(user, perspective = nil)
    vars = { id: plant.to_global_id_param }
    vars[:perspective] = perspective if perspective
    PlantApiSchema.execute(query, context: { current_user: user }, variables: vars)
       .dig('data', 'plant', 'scientificName')
  end

  it 'defaults to published content' do
    expect(run(build(:user, trust_level: 10))).to eq('Live name')
  end

  it 'returns staged content under DRAFT for a user who may edit' do
    expect(run(build(:user, trust_level: 10), 'DRAFT')).to eq('Draft name')
  end

  # The leak-prevention property. An anonymous caller cannot name the argument
  # into existence, and even naming it must not yield draft content.
  it 'never returns draft content to an anonymous caller' do
    expect(run(nil)).to eq('Live name')
    expect(run(nil, 'DRAFT')).to eq('Live name')
  end

  it 'never returns draft content to a read-only user' do
    expect(run(build(:user, trust_level: 1), 'DRAFT')).to eq('Live name')
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `docker compose run -e RAILS_ENV=test web bundle exec rspec spec/graphql/perspective_spec.rb`
Expected: FAIL, `Perspective` is not defined

- [ ] **Step 3: Write the enum and info type**

```ruby
# app/graphql/types/perspective_enum.rb
# frozen_string_literal: true

module Types
  # Which view of a record to return. The second read lens in this schema;
  # `language:` setting Mobility.locale is the first.
  #
  # PUBLISHED is the default precisely so that anonymous and mobile callers,
  # which never send the argument, cannot receive draft content. That is the
  # leak-prevention mechanism and it requires nobody to remember anything.
  class PerspectiveEnum < Types::BaseEnum
    graphql_name 'Perspective'
    value 'PUBLISHED', 'The published record.', value: :published
    value 'DRAFT', 'The record with staged changes applied. Requires edit permission.', value: :draft
  end
end
```

```ruby
# app/graphql/types/record_draft_info_type.rb
# frozen_string_literal: true

module Types
  # Metadata about a record's pending draft. Null when there is none.
  class RecordDraftInfoType < Types::BaseObject
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    field :author, String, null: true,
          description: 'Display name of the principal who started this draft.'
    field :last_editor, String, null: true,
          description: 'Display name of the principal who last edited it.'
    field :changed_fields, [String], null: false,
          description: 'Attribute names this draft changes.'
    field :is_stale, Boolean, null: false,
          description: 'True when the live record changed a drafted field since this draft was started.'

    def author
      object.author&.display_name
    end

    def last_editor
      object.last_editor&.display_name
    end

    def is_stale # rubocop:disable Naming/PredicateName
      Drafts::ConflictDetector.new(object).conflicted_fields.any?
    end
  end
end
```

`is_stale` depends on Task 6. Implement Task 6 first if executing out of order, or stub `is_stale` to `false` and replace it in Task 6 — the spec in Task 6 is what proves it.

- [ ] **Step 4: Write the shared field concern**

```ruby
# app/graphql/types/concerns/draft_fields.rb
# frozen_string_literal: true

module Types
  module Concerns
    # The `draft` metadata field, included by the four draftable types.
    # Deliberately no `data` field: staged values are read through the
    # perspective lens, not merged client-side.
    module DraftFields
      def self.included(base)
        base.field :draft, Types::RecordDraftInfoType,
                   null: true,
                   description: 'Pending staged changes, or null. Visible only to users who may edit.'
      end

      def draft
        return nil unless Pundit.policy(context[:current_user], object).update?

        object.record_draft
      end
    end
  end
end
```

Add `include Types::Concerns::DraftFields` to `PlantType`, `VarietyType`, `FamilyType`, and `CategoryType`.

- [ ] **Step 5: Add the argument to the four single-record queries**

In `app/graphql/types/query_type.rb`, for `plant` (and identically for `variety`, `family`, `category`):

```ruby
      argument :perspective,
               type: Types::PerspectiveEnum,
               required: false,
               default_value: :published,
               description: 'PUBLISHED (default) or DRAFT. DRAFT requires edit permission.'
```

and change the resolver:

```ruby
    def plant(id:, language: nil, perspective: :published)
      item_id = decode_global_id(id)
      Mobility.locale = language || I18n.locale
      record = Pundit.policy_scope(context[:current_user], Plant).find(item_id)
      apply_perspective(record, perspective)
    end
```

Add the shared helper to `QueryType`'s private section:

```ruby
    # Applies the draft overlay when DRAFT was asked for AND the caller may
    # edit. A reader holding only show? gets published content back rather than
    # an error: perspective is a view preference, not an assertion of rights,
    # and 403ing here would turn an ordinary page load into a failure for
    # anyone browsing.
    def apply_perspective(record, perspective)
      return record unless perspective == :draft
      return record unless Pundit.policy(context[:current_user], record).update?

      Drafts::Overlay.apply(record, record.record_draft)
    end
```

- [ ] **Step 6: Run the spec and the contracts**

Run: `docker compose run -e RAILS_ENV=test web bundle exec rspec spec/graphql/perspective_spec.rb spec/contracts/`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add app/graphql/types spec/graphql/perspective_spec.rb
git commit -m "feat(drafts): perspective lens and draft metadata field"
```

---

### Task 6: Conflict detection

**Files:**
- Create: `app/services/drafts/conflict_detector.rb`
- Create: `spec/services/drafts/conflict_detector_spec.rb`

**Interfaces:**
- Produces: `Drafts::ConflictDetector.new(draft).conflicted_fields -> Array<String>`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/services/drafts/conflict_detector_spec.rb
require 'rails_helper'

RSpec.describe Drafts::ConflictDetector do
  let(:plant) { create(:plant, scientific_name: 'Original', family_names: 'Original family') }

  it 'reports nothing when live has not moved' do
    draft = create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Draft' },
                                  base_updated_at: plant.updated_at)
    expect(described_class.new(draft).conflicted_fields).to be_empty
  end

  it 'reports a field both the draft and live changed' do
    draft = create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Draft' },
                                  base_updated_at: plant.updated_at)
    plant.update!(scientific_name: 'Changed under the draft')

    expect(described_class.new(draft).conflicted_fields).to include('scientific_name')
  end

  # The reason for field-level rather than timestamp-level detection. A coarse
  # live.updated_at > base_updated_at check fires on every SourceSynchronizer
  # run touching last_synced_at, which trains editors to click through warnings.
  it 'ignores live changes to fields the draft does not touch' do
    draft = create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Draft' },
                                  base_updated_at: plant.updated_at)
    plant.update!(family_names: 'Changed elsewhere')

    expect(described_class.new(draft).conflicted_fields).to be_empty
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `docker compose run -e RAILS_ENV=test web bundle exec rspec spec/services/drafts/conflict_detector_spec.rb`
Expected: FAIL, `uninitialized constant Drafts::ConflictDetector`

- [ ] **Step 3: Write the service**

```ruby
# app/services/drafts/conflict_detector.rb
# frozen_string_literal: true

module Drafts
  # Answers "did the live record change, under this draft, in a field the draft
  # also changes?"
  #
  # This is the one place PaperTrail is used by the drafts feature, and it is
  # the use PaperTrail is actually for: an immutable record of what happened to
  # the live row. Storing drafts in it was rejected; reading it to detect
  # collisions is exactly right.
  #
  # Field-level rather than timestamp-level on purpose. SourceSynchronizer,
  # ChangeHistory::Restorer, mobile and direct API callers can all move live
  # under a draft, and several of them touch bookkeeping columns on every run.
  # A coarse updated_at comparison would fire constantly and teach editors to
  # dismiss the warning.
  class ConflictDetector
    def initialize(draft)
      @draft = draft
    end

    def conflicted_fields
      return [] if @draft.blank?

      (live_changed_fields & @draft.changed_fields).sort
    end

    private

    def live_changed_fields
      versions = PaperTrail::Version
                 .where(item_type: @draft.draftable_type, item_id: @draft.draftable_id)
                 .where(created_at: @draft.base_updated_at..)

      versions.flat_map { |version| (version.changeset || {}).keys }.uniq
    rescue StandardError
      # A changeset that cannot be deserialized must not take down a page load
      # or block a publish. Treating it as "no detectable conflict" is the safe
      # direction: the publish still runs inside with_lock, and nothing is lost
      # because recordHistory keeps the overwritten value.
      []
    end
  end
end
```

`version.changeset` deserialization carries a known quirk: it yields enum STRINGS when the item row exists but raw INTEGERS on destroy or orphaned versions. This service only reads `.keys`, so it is unaffected — but do not extend it to compare values without handling that, and see `ChangeHistory::DiffBuilder` for the existing handling.

- [ ] **Step 4: Run the spec**

Run: `docker compose run -e RAILS_ENV=test web bundle exec rspec spec/services/drafts/conflict_detector_spec.rb`
Expected: PASS, 3 examples

- [ ] **Step 5: Replace the `is_stale` stub in `RecordDraftInfoType` if you stubbed it in Task 5, then commit**

```bash
git add app/services/drafts app/graphql/types/record_draft_info_type.rb spec/services/drafts
git commit -m "feat(drafts): field-level conflict detection via the audit trail"
```

---

### Task 7: publishDraft and discardDraft

**Files:**
- Create: `app/services/drafts/publisher.rb`
- Create: `app/graphql/mutations/publish_draft.rb`
- Create: `app/graphql/mutations/discard_draft.rb`
- Modify: `app/graphql/types/mutation_type.rb`
- Create: `spec/graphql/mutations/publish_draft_spec.rb`

**Interfaces:**
- Consumes: `Drafts::ConflictDetector` (Task 6), `DraftableAttributes` (Task 2)
- Produces: `publishDraft(recordId:, accessLevel:, force:)`, `discardDraft(recordId:)`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/graphql/mutations/publish_draft_spec.rb
require 'rails_helper'

RSpec.describe 'publishDraft' do
  let(:user) { build(:user, trust_level: 10) }
  let(:plant) { create(:plant, scientific_name: 'Live', visibility: :public) }
  let(:mutation) do
    <<~GRAPHQL
      mutation($input: PublishDraftInput!) {
        publishDraft(input: $input) {
          record { ... on Plant { id scientificName } }
          conflictedFields
          errors { code field message }
        }
      }
    GRAPHQL
  end

  def publish(force: false)
    PlantApiSchema.execute(
      mutation, context: { current_user: user },
      variables: { input: { recordId: plant.to_global_id_param, force: force } }
    )
  end

  it 'applies the draft to the live record' do
    create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Published' },
                          base_updated_at: plant.updated_at)
    publish
    expect(plant.reload.scientific_name).to eq('Published')
  end

  it 'destroys the draft' do
    create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Published' },
                          base_updated_at: plant.updated_at)
    publish
    expect(plant.reload.record_draft).to be_nil
  end

  it 'writes exactly one version, so history shows what the public saw' do
    create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Published' },
                          base_updated_at: plant.updated_at)
    expect { publish }.to change { plant.versions.count }.by(1)
  end

  it 'publishes a never-published record' do
    plant.update!(visibility: :draft)
    create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Published' },
                          base_updated_at: plant.updated_at)
    publish
    expect(plant.reload.publication_state).to eq('published')
  end

  it 'refuses when live moved under the draft, and keeps the draft' do
    create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Published' },
                          base_updated_at: plant.updated_at)
    plant.update!(scientific_name: 'Changed under the draft')

    result = publish
    expect(result.dig('data', 'publishDraft', 'conflictedFields')).to include('scientific_name')
    expect(plant.reload.scientific_name).to eq('Changed under the draft')
    expect(plant.record_draft).to be_present
  end

  it 'publishes anyway when forced' do
    create(:record_draft, draftable: plant, data: { 'scientific_name' => 'Published' },
                          base_updated_at: plant.updated_at)
    plant.update!(scientific_name: 'Changed under the draft')

    publish(force: true)
    expect(plant.reload.scientific_name).to eq('Published')
  end

  it 'keeps the draft when the publish fails validation' do
    create(:record_draft, draftable: plant, data: { 'scientific_name' => '' },
                          base_updated_at: plant.updated_at)
    publish
    expect(plant.reload.record_draft).to be_present
  end

  it 'is a no-op, not an error, when the draft changes nothing' do
    create(:record_draft, draftable: plant, data: {}, base_updated_at: plant.updated_at)
    result = publish
    expect(result.dig('data', 'publishDraft', 'errors')).to be_empty
  end
end
```

The empty-`scientific_name` case assumes a presence validation on it. Check `app/models/plant.rb` first and pick an attribute that genuinely fails validation; if none does, use `translations` set to `{}`, which cannot persist (Type::Serialized serialises `{}` to SQL NULL on a NOT NULL column).

- [ ] **Step 2: Run it to verify it fails**

Run: `docker compose run -e RAILS_ENV=test web bundle exec rspec spec/graphql/mutations/publish_draft_spec.rb`
Expected: FAIL, `PublishDraftInput` is not defined

- [ ] **Step 3: Write the publisher**

```ruby
# app/services/drafts/publisher.rb
# frozen_string_literal: true

module Drafts
  # The publish transaction: re-check the conflict authoritatively, apply the
  # draft through the ordinary update path, flip publication state on a first
  # publish, and destroy the draft.
  #
  # Applying through update! rather than assigning columns is what makes the
  # audit trail honest: one version, whose changeset is the real before/after,
  # with every validation, the OrganizedResource dual-write and the
  # FamilyAssignment mirror all running exactly as they do for a direct edit.
  class Publisher
    Result = Struct.new(:record, :conflicted_fields, :errors, keyword_init: true)

    def initialize(record:, force: false, access_level: nil)
      @record = record
      @force = force
      @access_level = access_level
    end

    def call
      draft = @record.record_draft
      return Result.new(record: @record, conflicted_fields: [], errors: []) if draft.blank?

      @record.with_lock do
        # The check at dialog-open time is advisory. This one is authoritative:
        # it runs inside the row lock, so nothing can slip in between.
        conflicts = ConflictDetector.new(draft).conflicted_fields
        return Result.new(record: @record, conflicted_fields: conflicts, errors: []) if
          conflicts.any? && !@force

        attributes = draft.data.slice(*DraftableAttributes.for(@record.class))
        attributes[:publication_state] = 'published' if @record.publication_state == 'draft'
        attributes[:access_level] = @access_level if @access_level.present?

        unless @record.update(attributes)
          # Deliberately does NOT destroy the draft. A failed publish must never
          # lose work.
          return Result.new(record: @record, conflicted_fields: [],
                            errors: @record.errors)
        end

        draft.destroy!
      end

      Result.new(record: @record, conflicted_fields: [], errors: [])
    end
  end
end
```

- [ ] **Step 4: Write the two mutations**

```ruby
# app/graphql/mutations/publish_draft.rb
# frozen_string_literal: true

module Mutations
  # Applies a record's pending draft to the live record.
  class PublishDraft < BaseMutation
    argument :record_id, ID, required: true,
             description: 'Relay global ID of the record whose draft should be published.'
    argument :access_level, Types::AccessLevelEnum, required: false,
             description: 'Access level to publish at. Only meaningful on a first publish.'
    argument :force, Boolean, required: false, default_value: false,
             description: 'Publish even though the live record changed under this draft.'

    field :record, Types::NodeType, null: true
    field :conflicted_fields, [String], null: false
    field :errors, [Types::MutationError], null: false

    def resolve(record_id:, access_level: nil, force: false)
      record = load_draftable(record_id)
      authorize record, :update?

      result = Drafts::Publisher.new(record: record, force: force, access_level: access_level).call

      {
        record: result.record,
        conflicted_fields: result.conflicted_fields,
        errors: result.errors.respond_to?(:full_messages) ? errors_from_active_record(result.errors) : []
      }
    end

    private

    # Decodes the global ID and confirms the type is actually draftable, so a
    # Specimen or Location ID produces a clean 404 rather than a NoMethodError.
    def load_draftable(record_id)
      type_name, id = GraphQL::Schema::UniqueWithinType.decode(record_id)
      raise ActiveRecord::RecordNotFound unless
        %w[Plant Variety Family Category].include?(type_name)

      Pundit.policy_scope(context[:current_user], type_name.constantize).find(id)
    end
  end
end
```

`discard_draft.rb` is the same shape: same `load_draftable`, same `authorize record, :update?`, body `record.record_draft&.destroy!`, fields `record` and `errors`.

Register both in `app/graphql/types/mutation_type.rb` beside the existing mutations. Confirm `Types::NodeType` is the right union/interface for a polymorphic return — if the schema has no such type, return the four concrete types via separate payload fields instead, or take the simpler route of four typed mutation pairs.

- [ ] **Step 5: Run the spec and the contracts**

Run: `docker compose run -e RAILS_ENV=test web bundle exec rspec spec/graphql/mutations/publish_draft_spec.rb spec/contracts/`
Expected: PASS, 9 examples plus contracts unchanged

- [ ] **Step 6: Commit**

```bash
git add app/services/drafts app/graphql/mutations app/graphql/types/mutation_type.rb spec
git commit -m "feat(drafts): publishDraft and discardDraft"
```

---

### Task 8: The hasPendingChanges list filter

Without a way to find drafts, the feature quietly accumulates orphans: a draft opened three weeks ago on a record nobody remembers is functionally lost.

**Files:**
- Modify: `app/graphql/resolvers/{plants,varieties,families,categories}_resolver.rb`
- Create: `spec/graphql/resolvers/has_pending_changes_spec.rb`

**Interfaces:**
- Produces: `hasPendingChanges: Boolean` option on the four collection queries

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/graphql/resolvers/has_pending_changes_spec.rb
require 'rails_helper'

RSpec.describe 'plants(hasPendingChanges:)' do
  let(:user) { build(:user, trust_level: 10) }
  let!(:with_draft) { create(:plant, visibility: :public) }
  let!(:without_draft) { create(:plant, visibility: :public) }

  before { create(:record_draft, draftable: with_draft, base_updated_at: with_draft.updated_at) }

  def ids(value)
    result = PlantApiSchema.execute(
      'query($v: Boolean) { plants(hasPendingChanges: $v) { edges { node { uuid } } } }',
      context: { current_user: user }, variables: { v: value }
    )
    result.dig('data', 'plants', 'edges').map { |e| e.dig('node', 'uuid') }
  end

  it 'returns only records with a pending draft when true' do
    expect(ids(true)).to contain_exactly(with_draft.id)
  end

  it 'returns only records without one when false' do
    expect(ids(false)).to include(without_draft.id)
    expect(ids(false)).not_to include(with_draft.id)
  end

  it 'returns everything when the filter is absent' do
    expect(ids(nil)).to include(with_draft.id, without_draft.id)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `docker compose run -e RAILS_ENV=test web bundle exec rspec spec/graphql/resolvers/has_pending_changes_spec.rb`
Expected: FAIL, `hasPendingChanges` is not a valid argument

- [ ] **Step 3: Add the option to each resolver**

Following the `search_object_graphql` idiom already used there:

```ruby
    option :has_pending_changes, type: Boolean, with: :apply_has_pending_changes_filter

    # EXISTS rather than a join: a join against a unique index would still be
    # correct, but EXISTS keeps the filter from affecting row multiplicity if
    # the uniqueness constraint is ever relaxed for named drafts.
    def apply_has_pending_changes_filter(scope, value)
      sub = RecordDraft.where(draftable_type: model_class.name)
                       .where('record_drafts.draftable_id = ' \
                              "#{model_class.table_name}.id")
      value ? scope.where(sub.arel.exists) : scope.where.not(sub.arel.exists)
    end
```

Substitute the concrete model per resolver if `model_class` is not available in that context.

- [ ] **Step 4: Run the spec**

Run: `docker compose run -e RAILS_ENV=test web bundle exec rspec spec/graphql/resolvers/has_pending_changes_spec.rb`
Expected: PASS, 3 examples

- [ ] **Step 5: Guard the list N+1**

The `draft` field on a list of 50 rows resolves per row. Add a batch loader (the codebase's existing approach — check what `perf-plants-nplusone` landed) keyed on `[draftable_type, draftable_id]`, and add a spec asserting a 20-row query issues one draft query rather than 20.

- [ ] **Step 6: Commit**

```bash
git add app/graphql/resolvers spec/graphql/resolvers
git commit -m "feat(drafts): hasPendingChanges filter so drafts can be found"
```

---

## Verification checklist

- [ ] `docker compose run -e RAILS_ENV=test web bundle exec rspec` — full suite green
- [ ] `docker compose run -e RAILS_ENV=test web bundle exec rubocop` — clean
- [ ] `spec/contracts/` passes **unchanged** — the mobile regression proof
- [ ] An anonymous query with `perspective: DRAFT` returns published content
- [ ] `RecordDraft` writes zero PaperTrail versions
- [ ] Publishing writes exactly one version
- [ ] No email, uid, or org name in any diff (public repo)
- [ ] `db/structure.sql` regenerated and committed

## Follow-on

The SPA half is a separate plan: `features/drafts/` (api, `useDraftState`, `DraftBanner`, `PublishDialog`, `PendingDraftCard`) plus four thin detail-page integrations and the history-drawer entry. Do not start it until this ships — the SPA plan depends on the exact field and argument names above.
