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

## The sandbox trap: a sandbox server is never anonymous

`require_token` (`application_controller.rb`, the `return if set_sandbox_user`
line) returns before it ever looks at the `Authorization` header, and
`set_sandbox_user` (further down the same file) then installs the fixed sandbox
user on every request. Everything below follows from that one early return.

- **No request is anonymous.** A request with no token, with a garbage token or
  with an expired token is all the same sandbox user, with the configured trust
  level (the local `.env` uses `10`, a super-admin) and any `SANDBOX_ORGS`
  memberships. A bad token is never rejected with a 401.
- **Anonymous behaviour cannot be observed there.** The public scopes (plants,
  images, categories and so on) show a super-admin everything, including
  private, draft and deleted rows. A check that "an anonymous client sees only
  public data" passes or fails for the wrong reason against a sandbox server.
  This is why an anonymous check script must fail against the compose `web`
  service on port 3000 and pass only against a server started with `SANDBOX`
  unset.
- **The compose stack is a sandbox.** The `.env` file the `web` service reads
  sets `SANDBOX=true`, and so does the CI workflow. Treat that container as the
  tool for admin SPA work only.
- **Reads can write.** `resolve_actor` runs for the sandbox user too, so the
  first request upserts a principal, a personal organization and any
  `SANDBOX_ORGS` mirror rows. Pointing a sandbox server at a copy of
  production data adds those rows to the copy.
- **It must never be set in staging or production.** The Terraform in `infra/`
  does not set it. A task that did would make every internet request a signed-in
  writer.

### Proving a server is anonymous

The `me` query is null exactly when the request is anonymous, so it is the
cheapest probe. Run it with no token:

```bash
curl -s -X POST http://localhost:3000/graphql \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ me { displayName } }"}'
```

`{"data":{"me":null}}` means anonymous. A non-null `me` means the server is in
sandbox mode, whatever its configuration is supposed to say. Scripts that make
an anonymity claim should assert this first and refuse to continue otherwise.

### Starting a genuinely anonymous local server

Unsetting `SANDBOX` is necessary but not sufficient. Off sandbox,
`require_token` builds the RSA verification key from `APPLICATION_JWT_SECRET`
on every request, tokenless ones included, and the placeholder value in a dev
`.env` is not a valid key, so every request fails with a 500
(`OpenSSL::PKey::RSAError`). Supply a throwaway public key as the secret. It
is only used to verify tokens, and the anonymous server will never be given
one:

```bash
JWT_PUB="$(openssl genrsa 2048 2>/dev/null | openssl rsa -pubout 2>/dev/null | sed '1d;$d')"
docker run --rm ... \
  -e SANDBOX=false \
  -e "APPLICATION_JWT_SECRET=${JWT_PUB}" \
  ...
```

Pass these after any `--env-file` so they win, then confirm with the `me`
probe above before trusting anything the server reports. In specs the same
two steps apply: stub `ENV['SANDBOX']` to `nil` and stub
`ENV['APPLICATION_JWT_SECRET']` to a generated key body (see
`spec/requests/image_translations_spec.rb`), or execute the schema directly
with `context: { current_user: nil }`.
