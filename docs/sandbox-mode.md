# Sandbox mode

Sandbox mode replaces JWT authentication with a fixed in-memory user, so the
API can be run locally without an IdP issuing tokens. It is a development
affordance: `set_sandbox_user` returns immediately unless `SANDBOX=true`, and
production never sets it.

| Variable | Default | Effect |
| --- | --- | --- |
| `SANDBOX` | unset | `true` bypasses JWT and authenticates every request as `sandbox@sandbox.com`. |
| `SANDBOX_TRUST_LEVEL` | `2` | The sandbox user's `trust_levels['plant']`. `2` = read/write, `>8` = admin, `>9` = super-admin (required for lookup CRUD). |
| `SANDBOX_ORGS` | unset | Organization memberships for the sandbox user. See below. |

## SANDBOX_ORGS

Without it, the sandbox user belongs only to its personal organization, which
leaves every organization-aware surface untestable locally: the admin SPA's
workspace switcher hides itself, organization capability checks never fire, and
the visibility facade only ever sees personal ownership.

The value is a comma separated list of entries, each `Name` or `Name:role`:

```bash
SANDBOX_ORGS='ECHO Asia Impact Center:org_admin,ECHO North America:editor'
```

- **Role** is an `OrganizationRole` name (`member`, `contributor`, `editor`,
  `steward`, `org_admin`), and defaults to `org_admin` when omitted. An entry
  naming an unknown role is skipped with a warning rather than granting
  nothing silently, since a typo would otherwise look like a capability bug.
- **Ids** are UUIDv5 values derived from the name, so a given name always maps
  to the same organization across restarts. This matters because a mirrored
  real organization adopts the claim id as its local primary key.
- **No seeding is required.** The claims flow through the same
  `resolve_actor` path as real JWT claims, and `mirror_claimed_organizations`
  upserts the `organizations` rows on the first request.

Two Docker specifics that cost time if you miss them:

- **Do not quote the value in `.env`.** Compose reads `.env` through
  `env_file`, which keeps quotes as part of the value rather than stripping
  them the way dotenv does. A wrapping pair is tolerated defensively, but
  unquoted is the intended form; spaces need no escaping.
- **Use `docker compose up -d web`, not `docker compose restart web`.**
  `restart` reuses the existing container with its baked-in environment, so it
  will not see the new variable. `up -d` recreates it.

To confirm it took effect:

```bash
curl -s -X POST http://localhost:3000/graphql \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ me { organizations { role organization { name kind } } } }"}'
```
