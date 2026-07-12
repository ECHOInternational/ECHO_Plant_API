# Authorization & the `plant` trust level

The Plant API has **no users table**. Every request is authorized from the JWT
issued by echocommunity's identity provider. The token carries a `user` object
with `trust_levels.plant` (an integer), and the API reads *only* that number to
decide what the caller may do. Permissions are therefore provisioned on the
**echocommunity IdP side**, per user — not in this codebase.

## The ladder (enforced in `app/models/user.rb`)

| `trust_levels.plant` | Capability | Method |
|---|---|---|
| `>= 1` | **read** — see public + own records | `can_read?` |
| `>= 2` | **write** — create; edit/soft-delete records **you own** | `can_write?` |
| `>= 9` | **admin** — edit/soft-delete **anyone's** records | `admin?` (`> 8`) |
| `>= 10` | **super-admin** — also hard-destroy, and CRUD the lookup tables (Tolerance, GrowthHabit, Antinutrient, ImageAttribute) | `super_admin?` (`> 9`) |

Each tier includes the ones below it. The exact boundary that surprises people:
**level 8 is _not_ admin** — `admin?` is `> 8`, so admin starts at **9**.

## Symptom → cause

- *"I can edit my own records but not others'."* → your token's `plant` level is
  in **2–8** (write, not admin). Raise it to **9** (edit everything) or **10**
  (full super-admin). This was a real support case (2026-07-12): an account
  provisioned at `plant: 8`, one below the admin threshold.
- *"401 on every write."* → `plant` is missing or `< 2`, or the token failed
  signature verification (`APPLICATION_JWT_SECRET` mismatch).
- *"403 / not-authorized on a lookup mutation."* → needs super-admin (`10`);
  `9` is not enough for lookup CRUD or hard-destroy.

The admin SPA (`plant_data_admin_interface`) reads the identical claim path and
the same thresholds (`src/features/auth/usePermissions.ts`) purely to show/hide
UI; the API enforces regardless of what the SPA renders.

## To grant someone admin/super-admin

Set their **`plant`** trust level to 9 (admin) or 10 (super-admin) in
echocommunity's permission system, then have them re-authenticate so a fresh
token is issued. Trust levels are per-domain (a user may be `general: 9` but
`plant: 8`), so raising one domain does not affect another.

> Do **not** lower the API thresholds to "fix" an under-provisioned account —
> they are read identically by the API and SPA, and lowering `admin?` would
> widen access for *every* level-8 user. Provision the account instead.
