# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

The ECHO Open Plant Database: Rails 8.1 / Ruby 3.4 (YJIT), PostgreSQL, **GraphQL-only** — the only routes are `POST /graphql` and healthchecks; there is no HTML UI. Deployed on ECS Fargate via Terraform (`infra/`); staging (plant-api-staging.echocommunity.org) auto-deploys from CI, production (plant-api.echocommunity.org) is behind a manual gate in the Deploy workflow. Default branch: `master`.

Plant administration is **not** in this repo — it is a separate SPA (its own repo) at plant-admin.echocommunity.org, talking to this API over GraphQL.

Workspace note: when this repo is checked out inside the plant-data-migration workspace (`../CLAUDE.md`, `../project_prompt.md`), those files define the cross-system migration context and the production-safety rules that govern all work here.

## Commands

```bash
# All dev/test DB config points at host "db" (the docker-compose service name):
# run inside the container (docker-compose exec web ...) or resolve "db" yourself.
# docker-compose requires a .env file (not committed) — SANDBOX=true is the key entry.
docker-compose up                            # Postgres + web on :3000 (+ pgadmin :3080, mailcatcher :1080)

bundle exec rails db:create db:schema:load   # loads db/structure.sql
SANDBOX=true SANDBOX_TRUST_LEVEL=10 bundle exec rspec   # all tests (mirrors CI env)
bundle exec rspec spec/models/plant_spec.rb:42          # single test
bundle exec rubocop
bundle exec rails graphql:schema:dump        # regenerate schema.graphql after GraphQL changes
```

## Key facts

- **`db/structure.sql` is the authoritative schema** (`schema_format = :sql`). `db/schema.rb` exists but is frozen at 2020 and badly stale — never trust it.
- **CI diff-gates `schema.graphql`**: any change to GraphQL types/mutations/resolvers must be followed by `rails graphql:schema:dump`, with the regenerated snapshot committed, or CI fails.
- Data model: `Plant` → `Variety` → `Specimen`, plus lookup tables (antinutrients, tolerances, growth habits, categories) linked through join models; UUID primary keys throughout; PaperTrail version history on records.
- i18n via Mobility (JSONB `translations` column per table), **pinned at 1.2.9** — the Gemfile comment documents a container-backend regression; don't bump without running `spec/models/mobility_compat_spec.rb`.
- **Auth: the API verifies but never issues JWTs** (RS256, `Authorization: Token ...`); tokens come from ECHOcommunity's Doorkeeper IdP. There is no users table — `User` is a plain Ruby object hydrated from the JWT (uid, email, trust_levels). Authorization is Pundit policies + a trust-level ladder + an organization/ownership layer.
- `SANDBOX=true` bypasses JWT for local dev and tests (fixed `sandbox@sandbox.com` user; tune with `SANDBOX_TRUST_LEVEL` — 2 = write, >8 = admin, >9 = super-admin — and `SANDBOX_ORGS`; see `docs/sandbox-mode.md`).

## Docs to read before deep work

- `docs/MODERNIZATION-2026-07.md` — the July 2026 EB→ECS / Rails 6→8.1 / admin-rollout overhaul; recent history and hard-won operational gotchas.
- `docs/authorization-trust-levels.md` — the trust-level ladder.
- `docs/ownership-current-state.md` and `docs/ownership-redesign/{design,discovery,rollout}.md` — the accepted organizations/ownership redesign (IdP-authoritative orgs, membership via JWT claims).
- `infra/README.md` — ECS/Terraform layout; shared ALB with ECHOcommunity, listener-rule warnings.
