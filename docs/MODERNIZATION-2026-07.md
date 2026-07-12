# ECHO Plant API — Modernization Program (July 2026)

A record of the platform migration, framework upgrade, and admin-interface
rollout completed 2026-07-10 → 2026-07-12. Written so a future maintainer can
understand what changed, why, and where the follow-up work lives.

## Executive summary

| Dimension | Before | After |
|---|---|---|
| Deploy platform | Elastic Beanstalk (Ruby 2.7 / AL2, EOL), hand-deployed via CodePipeline | ECS Fargate, GitHub Actions CI/CD with OIDC |
| Framework | Rails 6.0.4 | Rails 8.1.3 |
| Runtime | Ruby 2.7.8 (EOL) | Ruby 3.4.10 + YJIT |
| GraphQL | graphql-ruby 1.11.5 | 2.3.23 |
| Security alerts (Dependabot) | 121 | 0 |
| DB auth | md5 (un-rotatable, EB libpq too old for SCRAM) | scram-sha-256, rotatable |
| PaperTrail version history | silently broken since 2020 (`item_id` bigint = 0) | 20,190 rows repaired, 100% linked |
| Mobile cache query | 953 SQL queries / ~2.5–3.6 s | 3 queries / ~0.3–0.7 s |
| Admin interface | not deployed | live at plant-admin.echocommunity.org (OAuth2 + PKCE) |

Everything shipped through the same loop: fresh implementer subagent → adversarial
review → gated PR → staging deploy → (manual gate) production. ~25 backend PRs
(#43–#73) plus the admin rollout. No GraphQL contract break; no unplanned outage.

---

## Workstream A — Elastic Beanstalk → ECS Fargate

**Cutover 2026-07-10 12:26:50Z.** Production moved from EB to ECS by swapping a
shared-ALB listener rule (DNS untouched, instant rollback available).

Key infrastructure (Terraform, in `infra/`):
- `bootstrap/` — S3 state bucket `echo-terraform-state-382724554857` (per-app key prefixes).
- `global/` — ECR repo `plant-api` (immutable tags), GitHub OIDC deploy role
  `gha-plant-api-deploy` (trust locked to repo + master/staging/production).
- `modules/plant-api/` + `envs/{staging,production}/` — dedicated ECS clusters,
  task defs, target groups + listener rules on the **shared** `ECHOcommunity-load-balancer`,
  tasks in the single existing private subnet, autoscaling, Secrets Manager injection.
- CI/CD: `.github/workflows/ci.yml` (rspec + rubocop + docker build) and
  `deploy.yml` (build once → staging auto → **production manual gate** → same image digest).

Routing: `plant-api.echocommunity.org` → ALB host rule **priority 6** →
`plant-api-production-tg`. (The old EB path was the `/*` catch-all rule at priority 16 —
never recreate that.)

Hard-won operational facts (also in the infra README):
- Container healthcheck uses `ruby -rnet/http`, NOT curl (absent from the slim image).
- Secrets inject at task start — seed `plant-api-<env>/*` before first deploy, or
  force-new-deployment after.
- ECR is immutable-tag; pipeline deploys use 12-char git SHA tags.
- Production-boot gates must run against the `--target production` image, not the
  compose dev image (only place runtime-linkage regressions surface).

**EB decommissioned 2026-07-11** (issue #38 closed): environment terminated,
CodePipeline deleted, `plantapi_app` role rotated md5 → scram-sha-256 (the ECS
image's modern libpq made this possible), temp setup access revoked.

---

## Workstream B — Rails 6.0.4 → 8.1.3 (the ladder)

19 planned steps, one variable per step, each gated by a **safety net built in Step 1**:
a committed `schema.graphql` + CI drift gate, plus contract specs (`spec/contracts/`)
and later observe-then-pin compat specs (`spec/models/*_compat_spec.rb`) — ~40 tripwire
examples pinning the public GraphQL contract, PaperTrail YAML history, and Mobility
translations. These caught real problems the ordinary suite missed.

The rungs (as merged): gem hygiene → Rails 6.1 → graphql 1.13 bridge → graphql 2.0 →
mobility 1.2 → paper_trail (moved early) → Rails 7.0 → **Ruby 3.1** → Rails 7.1 →
graphql 2.3 → Ruby 3.3 → Rails 7.2 → Rails 8.0 → **Ruby 3.4 + YJIT** → **Rails 8.1**.

Notable discoveries and decisions (each documented in its step report / commit):
- **PaperTrail YAML / Psych 4:** PT calls `::YAML.load` directly (not AR's coder), so
  Rails' `yaml_column_permitted_classes` can't fix it. Solved with a custom safe-load
  serializer (`lib/paper_trail_yaml_serializer.rb`) whose permitted-class set was
  **proven against every production payload** (only BigDecimal + Range tagged; plus a
  lazy `ActiveRecord::Point` guard for Location coordinates — forward-risk only).
- **Mobility held at 1.2.9:** the compat spec caught a genuine mobility 1.3.x
  container-backend write regression (nils just-written translations). Held pending an
  upstream fix; `partial_inserts = true` pin stays with it.
- **Rails 8.0 Relation ivar rename** (`@klass`→`@model`) broke the held mobility's query
  plugin → `lib/mobility_query_rails8_compat.rb` (behaviorally guarded, self-disabling,
  drift-guarded by `spec/models/policy_scope_loaded_drift_spec.rb` and the 5
  `spec/queries/*` files). Retire when mobility unholds.
- **YJIT** auto-enabled by Rails 7.2 defaults on Ruby 3.3 (two rungs early); made explicit
  via `RUBY_YJIT_ENABLE=1` in the production Docker stage.
- SDL cosmetic drift (graphql printer changes) accepted twice via graphql-inspector +
  SPA-codegen sign-off; each verified additive/description-only.

Final verification: pre-upgrade-captured global ID replays identically on 8.1; six
cross-version response diffs byte-identical (prod 6.0 vs staging 8.1); SPA codegen
order-only; suite 1300+/0.

---

## Post-promotion work

Applied to production after the Rails 8.1 promotion (2026-07-11), each reviewed + gated:
- **paper_trail 16 → 17** (silences the AR-8.1 advisory).
- **`versions.item_id` repair** — migration converting bigint→uuid and backfilling the
  record id from the YAML payloads (two passes: bare then quoted-uuid for old-era YAML).
  **20,190/20,190 rows linked, 0 unresolved.** `record.versions` works for the first time.
  The migration is bidirectionally compatible (old code writes correct uuids to the new
  column — verified by running the old image against a migrated DB).
- **Coded-404 unification** — all 10 single-object queries now return the same coded-404
  as `node()` for malformed IDs (was a raw 500 on Rails 6).
- **RuboCop 0.92 → 1.88** — removed three Ruby-3-era workarounds; grandfathered legacy
  offenses (file-scoped), NewCops enabled.
- **N+1 elimination** — the mobile cache query went 953→3 queries. A review caught a
  CRITICAL in the first cut (an `includes+references` truncation corrupting
  `primaryCommonName` for 67/238 filtered results) — fixed via EXISTS subqueries.
  Production tasks bumped to 1 vCPU / 2 GB (serialization is CPU-bound at this data size).
- **puma 6 → 8** — cleared the last two Dependabot alerts (dashboard now 0).

---

## Admin interface — production deployment

React 19 SPA (`plant_data_admin_interface`), live at **plant-admin.echocommunity.org**.
- **Hosting** (`infra/production/` in that repo): private S3 + CloudFront (OAC) + Route53
  alias on the wildcard cert; CSP + HSTS response headers; SPA deep-link error rewrites.
- **Deploy**: `.github/workflows/deploy.yml`, OIDC role `gha-plant-admin-deploy`, push to
  main → build → S3 sync → CloudFront invalidation. Seven GitHub repo variables drive it.
- **Auth**: OAuth2 authorization-code + **PKCE** (RFC 7636) against the echocommunity
  Doorkeeper IdP. Public/non-confidential/fully-trusted client. A security review removed
  a token-injection fallback and added the CSP/HSTS before ship. User-verified
  login + logout; the issued token validates at the production API with the
  `trust_levels['plant']` claim.
- CSP `img-src` includes `images.echocommunity.org` (the CDN render host — distinct from
  the raw `images-us-east-1.echocommunity.org` bucket used for presigned PUT uploads).

---

## Open / optional follow-ups (none blocking; systems are healthy)

- **Mobility unhold** to a fixed release > 1.3.2 (when upstream ships it) — then remove the
  Rails-8 query shim and the `partial_inserts` pin together; the compat + drift specs gate it.
- **graphql 2.4+ visibility-system migration** — an internals rewrite; own gated step. This
  app has zero custom `visible?` logic, so expected to be small. 2.3.23 emits no
  visibility warnings today.
- **Trigram (`pg_trgm`) search index** — optional; the N+1 fix already made the app fast,
  but leading-wildcard ILIKE search remains a scan. Would make fuzzy search index-fast.
- **Account-wide secret-rotation lambda** — no secret in the account rotates automatically
  today; `plantapi_app` is now SCRAM and rotatable, so a schedule is straightforward when wanted.
- **EB IAM roles** — the account-default `aws-elasticbeanstalk-*` roles can be deleted for
  tidiness (harmless to keep; zero cost).
- Minor: images bucket CORS is `AllowedOrigins: *` (could be tightened to the admin origin).

## Pointers

- Terraform: `infra/` (API) and `plant_data_admin_interface/infra/production/` (admin).
- CI/CD: `.github/workflows/{ci,deploy}.yml` in each repo.
- Custom serializers / shims: `lib/paper_trail_yaml_serializer.rb`,
  `lib/mobility_query_rails8_compat.rb`.
- Tripwire specs: `spec/contracts/`, `spec/models/*_compat_spec.rb`,
  `spec/models/paper_trail_item_id_spec.rb`, `spec/models/policy_scope_loaded_drift_spec.rb`.
- Rollback: re-run the Deploy workflow (workflow_dispatch) with a prior git SHA.
