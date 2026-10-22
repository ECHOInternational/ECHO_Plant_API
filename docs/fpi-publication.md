# FPI publication waves

How Food Plants International (FPI) plants become public in this API, and how
that is undone. FPI plan tasks API-10 to API-16 (the plan lives in the
ECHOcommunity repository, `docs/superpowers/plans/2026-10-22-fpi-plant-presentation.md`).

The API owns publication (decision D-007). ECHOcommunity reads public plants
anonymously and builds pages from them, so making a plant public here is what
puts an FPI page on the public site, and making it private again takes it off.

## Pieces

| Piece | Where | What it does |
|---|---|---|
| Quality rule | `data_sources.publication_rule`, `app/models/publication_rule.rb` | The single quality setting (plan decision Q2). FPI: at least one image, or at least 500 characters of English description + uses + cultivation. GraphQL `Plant.meetsQualityBar`. |
| Wave ledger | `publication_waves`, `publication_wave_items` | One row per wave (key `fpi-w1`, state, selector, rule snapshot, digest, counts); one item per plant or image a wave changed, with the exact visibility columns before (`prior`) and after (`applied`). Items are not versioned. |
| Selector | `lib/publication_waves/selector.rb` | Chooses the plants and computes the digest. |
| Publisher | `lib/publication_waves/publisher.rb` | Makes the selected plants and their private images public. |
| Unpublisher | `lib/publication_waves/unpublisher.rb` | Puts back exactly what a wave changed. |
| Rake tasks | `lib/tasks/publication.rake` | `report`, `set_rule`, `publish_wave`, `unpublish_wave`. |
| Workflow | `.github/workflows/ops-publication.yml` | Runs one task as a one-off ECS task on staging or production. |
| Rollback guard | `lib/fpi_rollback.rb` | `fpi:rollback` refuses to delete public or wave plants without `FORCE_PUBLIC=true`. |

## What a wave selects

The base set is the data source's plants that are owned by the data source's
own organization, not deleted, and published with organization access (legacy
visibility private). Two kinds are left out and counted in the report:

- plants in an active wave (`applying`, `applied` or `unpublishing`);
- plants with an open `source_deletion` sync conflict.

Selectors:

- `quality`: the base set filtered by the publication rule (wave 1);
- `remaining`: the whole base set (later waves);
- `ids`: the base set restricted to `IDS=uuid,uuid,...`.

`LIMIT=N` keeps the first N by id, for a canary.

The digest is a sha256 over the selector, its parameters, the rule, the
selected plant ids and the ids of the private images that would be flipped. An
apply must quote it (`EXPECTED_DIGEST`), so it publishes exactly what the
reviewed dry run counted. Anything that changes the selection in between
changes the digest, and the apply refuses.

## What publish and unpublish change

`publish_wave`, per plant, in one transaction: set `access_level` to `public`
(the OrganizedResource dual-write sets legacy `visibility` to public), and set
each of the plant's PRIVATE images to public. Draft and deleted images are left
alone. The image writes run under `no_touching`, so the plant gets exactly one
new version. Every version is attributed to the `ops` service principal and
carries `metadata.origin = wave_publish` with the wave id and key.

`unpublish_wave`, per plant, in one transaction:

- an item whose row still equals `applied` is put back to `prior` (restored);
- an item whose row changed since is left alone and counted (drift);
- an item whose row no longer exists is counted (missing);
- a public image on a restored plant that was created after the wave started
  and is not a wave item (a new upstream image, created public because its plant
  was public) is made private and recorded as an `unpublish_sweep` item.

Neither task touches anything else. `updated_at` moves forward, as it must,
so ECHOcommunity's delta projection sees the change.

The FPI sync never changes visibility (`visibility`, `access_level` and
`publication_state` are on the synchronizer's DENY_LIST, and it creates plants
private), and a source deletion only opens a conflict. So a sync neither undoes
a wave nor publishes anything by itself. New FPI images on an already-public
plant are created public (FpiImageImporter, API-6).

## Running it

Every write task takes the shared ops advisory lock (`lib/ops_advisory_lock.rb`),
dry runs included, and refuses to start while another FPI or publication write
task holds it. `publication:report` is read-only and does not take it.

```bash
bin/rails publication:report
RULE='{"version":1,"locale":"en","text_fields":["description","uses","cultivation"],"min_text_chars":500,"image_suffices":true}' \
  bin/rails publication:set_rule                       # dry run; APPLY=true writes
SELECTOR=quality bin/rails 'publication:publish_wave[fpi-w1]'          # dry run: counts + digest
SELECTOR=quality APPLY=true EXPECTED_DIGEST=<digest> bin/rails 'publication:publish_wave[fpi-w1]'
bin/rails 'publication:unpublish_wave[fpi-w1]'                          # dry run
APPLY=true bin/rails 'publication:unpublish_wave[fpi-w1]'
```

`SOURCE` selects the data source by `source_system_key` (default `fpi`).
`NOTES` is stored on the wave and may not contain '@'.

On staging and production, use the **Ops - Publication waves** workflow
(`workflow_dispatch` only). Its gate (`.github/scripts/publication-gate.sh`)
requires `confirm_apply` to be exactly `PUBLISH-WAVE-APPLY` for any apply, and
`expected_digest` for a `publish_wave` apply; the task job runs only on the
gate's verdict. Production also waits for the environment's required reviewers.
Its concurrency group is shared with `ops-fpi.yml`, but that is only a second
layer: GitHub silently cancels an older pending run in the same group, and the
waiter gives up after 2 hours while the ECS task keeps running. The advisory lock
is the real mutual exclusion. Never take a staging or rehearsal digest to
production: run a fresh production dry run.

A re-run is safe. A wave interrupted mid-apply stays `applying`; run the same
apply again (same key, same digest) and it continues with the plants still
pending. Re-running an applied wave, or unpublishing an unpublished one, changes
nothing. A wave key is never reused: after an unpublish, publish again with a new
key.

## Public logs: counts only

This repository is public, and so are its Actions logs. The tasks print wave
keys, selectors, digests and integers, never an organization, principal, author
or email. `spec/tasks/publication_rake_spec.rb` runs every task over fixtures
whose personal organizations are named after email addresses and fails if the
output contains '@' or any organization or principal name. Wave notes are
validated to contain no '@'.

## Report fields

| Field | Meaning |
|---|---|
| `plants`, `images` | Selected plants, and their private images that would be flipped |
| `safety_poisonous`, `safety_caution`, `edibility_uncertain_only` | Safety breakdown of the selection |
| `echo_twins` | Selected plants whose normalised scientific name equals a public plant of another source (an ECHO sheet) |
| `open_drafts` | Selected plants with an unpublished draft |
| `excluded_in_active_wave`, `excluded_open_source_deletion` | Base-set plants left out, and why |
| `items` | Ledger items by type, origin and state |
| `preview` | (unpublish dry run) what an apply would restore, leave as drift, find missing, or sweep |

## fpi:rollback and waves

`fpi:rollback` deletes FPI plants outright. Once a wave has made them public that
removes pages from the public site, so an apply refuses while any target plant is
public or in an active wave, unless `FORCE_PUBLIC=true`. Its dry run prints
`public_plants` and `active_wave_items`. Forced removal keeps the wave items (they
are the ledger); `unpublish_wave` then counts those rows as missing.

## Measured (local production copy, 2026-10-22)

See the waves pull request for the timings of the dry run, apply and unpublish on a
clone of the production database (8,172 plants, 11,986 images for `quality`) and
the empty before/after diff that proves exact rollback.
