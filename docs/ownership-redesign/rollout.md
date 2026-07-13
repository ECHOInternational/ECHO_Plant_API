# Ownership Redesign — Deployment & Rollback Runbook

*Companion to design.md (the what/why) and discovery.md (verified current state). This is the operator's sequence. Nothing here deploys itself; every stage is a human-controlled action. Written against the actual topology: API on ECS Fargate (staging auto / production manually gated), IdP on ECS Fargate (staged phases), SPA on S3+CloudFront (push-to-main deploys immediately), mobile app frozen.*

## Stage S1 — IdP: organizations + claim (branch `plant-org-memberships`)

**Deploy:** ECHOcommunity via its normal pipeline (staging soak, then production web service).
**Contains:** `organizations` + `organization_memberships` tables, admin UI under `/admin/organizations`, additive `user.organizations` JWT claim (absent when a user has no active memberships), `plant_identity:export` rake task.
**Pre-deploy checks:** run its migrations on staging; verify a normal login token payload is byte-identical for a user with no memberships (the claim key must be absent).
**Post-deploy:** create the **ECHO organization** in the admin UI; assign staff memberships (per D3: current trust-9/10 holders get editor/steward/org_admin as appropriate). Record the ECHO org UUID — the API backfill needs it.
**Rollback:** redeploy previous image. The claim is additive; no consumer requires it. Tables can stay (inert).

## Stage S2 — API: additive schema + shadow identity (commits through Phase B)

**Deploy:** normal pipeline (build → staging auto → production gate). The `-migrate` one-off task applies migrations `20260713000001..7` (1–6 = principals/organizations/data_sources/sync_conflicts/ownership columns/versions.metadata; 7 = `source_snapshot`; all additive; small tables; new indexes on visibility/owned_by are plain CREATE INDEX — table sizes make lock time negligible; if plants ever grows large, switch to CONCURRENTLY). All migrations are safe to apply while the old code version is still serving (new columns are nullable, new tables inert to old code); the pipeline runs the migrate task before the service update.
**Behavior change surface:** principal/personal-org upsert per authenticated request; PaperTrail versions gain metadata; soft-delete mutations authorize `:soft_delete?` (legacy owner/admin behavior identical); admins may now hard-delete images (documented intentional widening); org capabilities are live but inert until records carry owner_organization_id (S3) and tokens carry claims (S1).
**Verify on staging:** full suite in CI; smoke: anonymous plants query, authenticated create (check principals/organizations rows appear), soft-delete + restore round-trip, mobile contract specs.
**Rollback:** redeploy previous image. New tables/columns are ignored by the old code. Do NOT roll back migrations (additive; leave in place).

## Stage S3 — Backfill (rake, human-run per environment)

1. On IdP production: `bundle exec rake plant_identity:export OUTPUT=...`. The export JSON contains **PII** (emails, display names). Transfer it over an encrypted channel only — e.g. write to a private S3 path the API migrate task can read via IAM, or an SSM SecureString — never SCP to a laptop, email, or a public bucket. Delete the file from both ends after the backfill.
2. **Before DRY_RUN=0, check for stray `sandbox@sandbox.com`-owned rows in the target DB** (`SELECT count(*) FROM plants WHERE owned_by = 'sandbox@sandbox.com'` and likewise for the other four tables). `sandbox@sandbox.com` is in `SHARED_EMAILS` and maps to the ECHO org; production should have none (sandbox is a dev-only guard), but a promoted dev dump could carry some. Confirm the count is zero or intended.
3. Staging rehearsal first (staging has a prod-shape dump): `rake ownership:backfill MAPPING=... ECHO_ORG_ID=<uuid>` in DRY_RUN (default), review the report (unmapped emails, counts), then `DRY_RUN=0`, then `rake ownership:verify` (exit 0 = clean; exit 1 lists violations, including any `visibility=deleted` row with a null `deleted_at`).
4. Production: same sequence. Idempotent and resumable; re-runs skip already-filled rows.
**Rollback:** none needed — backfill writes only the new nullable columns and new tables; legacy authorization ignores them entirely. **Caveat:** re-running only fills rows whose `owner_organization_id` is still null; a row backfilled with an *incorrect* owner is NOT corrected by a re-run (the resumability filter skips it). To fix mis-mapped rows, null their `owner_organization_id`/`source_organization_id`/`created_by_principal_id` for the affected set (a targeted script) and re-run, or correct them directly.

## Stage S4 — API: new GraphQL surface + transition gates (Phase C+)

**Contains:** capability fields, organization/principal/publication fields, acting-org create argument, restore/transfer mutations, deletion-transition authorization gates, legacy-arg usage logging.
**Verify:** contract specs (mobile documents) green; capability/Pundit agreement specs green; staging smoke with a real echocommunity token carrying an organizations claim.
**Rollback:** redeploy previous image (schema untouched).

## Stage S5 — SPA update

Codegen against the deployed staging schema; capabilities replace `owns()`; org display; acting-org picker (only shown for multi-org users). Deploys on push to main (no gate!) — merge only after S4 is in production.
**Rollback:** re-sync previous build from the S3 versioned history / redeploy prior commit.
**POINT OF NO RETURN:** once S5 is live, the SPA queries capability fields (`canEdit`/`canDelete`/`canRestore`) and the new org/publication fields that exist only on the S4+ schema. **Do NOT roll S4 back while S5 is deployed** — the SPA would break on missing-field errors. If S4 must be reverted, revert S5 (re-sync the prior SPA build) first. This is why S5 merges only after S4 is confirmed stable in production.

## Stage S6 — Cutover observation (flagged)

Set `ORG_AUTHZ_CUTOVER=log_only` on the API. This does NOT change enforcement: the legacy email/trust-9 branches keep granting access exactly as before. What it adds is a structured `authz.legacy_divergence` log event (implemented in `OwnedResourcePolicy#log_legacy_divergence`) emitted whenever an access is granted **only** by a legacy branch and would be denied once legacy authorization is removed (fields: action, record type/id, principal id, owner org id — no PII). A soak window with **zero** such events is the evidence gate for S7. The enforcement flip (removing the legacy branches) is part of S7 cleanup, not this stage, because the mobile fleet keeps depending on legacy owner behavior until each user's records live in their personal org (which the backfill guarantees). In practice S6 is observation, not behavior change.

## Stage S7 — Deferred cleanup (separate change, later)

Prerequisites, each with evidence:
- Zero `authz.legacy_divergence` events over an agreed window.
- Staff trust-9 accounts hold equivalent ECHO-org memberships (IdP admin export).
- Mobile app release consuming capability fields shipped + adoption threshold agreed (or product accepts the legacy window indefinitely for mobile).
Then: demote trust-9 global admin to ECHO-org roles, remove legacy email branches from policies, enforce NOT NULL on owner_organization_id/source_organization_id/created_by_principal_id, remove deprecated-field usage logging, update docs.

## Observability (added across S2–S4)

- `authz.denied` structured log: policy, action, record type/id, decision source (legacy|org|superuser), principal id. Never tokens/emails-in-clear beyond what owned_by already exposes.
- `authz.legacy_divergence` (S6): would-be-denied-under-new-model decisions.
- `legacy_contract.visibility_arg` counter: update mutations receiving the legacy visibility argument (old-client usage signal for S7 evidence).
- `rake ownership:verify`: invariant report — records missing owner/source/creator, facade/column disagreements, cross-org children counts, duplicate (data_source, source_record_id).
- Backfill dry-run/report output retained as deploy artifacts.

## Compatibility matrix (tested combinations)

| Client | Server | Outcome |
|---|---|---|
| Mobile (frozen) | pre-S2 | baseline (contract specs encode it) |
| Mobile (frozen) | S2–S6 | identical behavior — contract specs + visibility facade + legacy-union policies |
| SPA (current) | S2–S4 | identical; new fields unused until S5 |
| SPA (S5) | S4+ | full new behavior |
| SPA (S5) | pre-S4 server | prevented by sequencing (merge S5 only after S4 in prod) |
| Anonymous | all stages | published+public reads only, unchanged |
