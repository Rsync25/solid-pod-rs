# Sprint 12 PRD: JSS v0.0.60–v0.0.71 Parity Close

**Date**: 2026-05-06
**Scope**: 10 implementation items (P0–P2) across 4 bounded contexts
**Reference**: ADR-058, JSS commits abc8165..6d58cc4

---

## Objective

Close the feature drift that accumulated during JSS's v0.0.60–v0.0.71
release cycle (12 releases, 4,184 insertions). Priority is security
hardening (P0), then IdP/security completeness (P1), then AP federation
interop (P2).

---

## Implementation Items

### P0 — Security Ship-Blockers

#### 1. Size-capped ACL parsing (safeJsonParse equivalent)
**BC**: Security Primitives
**Files**: `crates/solid-pod-rs/src/wac/parser.rs`
**JSS ref**: `src/wac/parser.js` commit `204fdfb`

- Add `MAX_ACL_BYTES` constant (default 1 MiB, configurable via `JSS_MAX_ACL_BYTES`)
- In `parse_turtle_acl` and JSON-LD ACL paths, reject input exceeding `MAX_ACL_BYTES` with 413
- Wire limit from `SecurityConfig` or `ExtrasConfig::max_acl_bytes`
- Tests: oversized ACL → 413, normal ACL passes

#### 2. Iterative path sanitization in subdomain resolver
**BC**: Security Primitives
**Files**: `crates/solid-pod-rs/src/multitenant.rs`
**JSS ref**: `src/utils/url.js` commit `2569811`

- Change `SubdomainResolver::resolve` pod-name extraction to use iterative `..` removal (loop until stable)
- Currently we have `is_file_like_label` which short-circuits but doesn't iteratively sanitize the pod name itself
- Tests: `....//` bypass, `..%2F..` double-encoded, normal names unaffected

### P1 — Security + IdP Completeness

#### 3. DNS resolution failure blocks request
**BC**: Security Primitives
**Files**: `crates/solid-pod-rs/src/security/ssrf.rs`
**JSS ref**: `src/utils/ssrf.js` commit `4dbf039`

- `resolve_and_check` already returns `Err` on DNS failure
- Ensure the error variant is unambiguously `DnsResolutionFailed` (not generic)
- Document that callers MUST short-circuit on this error (not fall through)
- Add test: unresolvable hostname → blocked

#### 4. `.account` in dotfile allowlist
**BC**: Security Primitives
**Files**: `crates/solid-pod-rs/src/security/dotfile.rs`, `crates/solid-pod-rs/src/config/schema.rs`
**JSS ref**: commit `32c0db2`

- Add `.account` to `default_dotfile_allowlist()` in `schema.rs`
- Add `.account` to the static allowlist in `dotfile.rs`
- Test: `.account` path passes filter

#### 5. Minimum password length validation
**BC**: Identity Provider
**Files**: `crates/solid-pod-rs-idp/src/credentials.rs`
**JSS ref**: `src/idp/accounts.js` commit `1feead2`

- Add `MIN_PASSWORD_LENGTH = 8` constant
- In `authenticate` / registration flow, reject passwords shorter than 8 chars
- Return typed error `PasswordTooShort { min_length: usize }`
- Test: 7-char password rejected, 8-char accepted

### P2 — ActivityPub Federation

#### 6. Outbox POST (Note → Create wrapping + delivery)
**BC**: ActivityPub Federation
**Files**: `crates/solid-pod-rs-activitypub/src/outbox.rs`
**JSS ref**: `src/ap/routes/outbox.js` commit `25fa813`

- Add `handle_outbox_post` that accepts raw Note (or Create wrapper)
- If body is a Note, wrap in Create activity with generated ID + timestamps
- Save to store, then trigger delivery to follower inboxes
- Return 201 with Location header
- Tests: raw Note POST → Create wrapping, Create POST passthrough, delivery triggered

#### 7. User-Agent header on federation fetches
**BC**: ActivityPub Federation
**Files**: `crates/solid-pod-rs-activitypub/src/delivery.rs`, `src/http_sig.rs`
**JSS ref**: commit `8247293`

- Configure `reqwest::Client` with `User-Agent: solid-pod-rs-activitypub/0.4.0`
- Apply to both delivery POST and actor/inbox discovery GET
- Test: mock server verifies User-Agent header present

#### 8. AP actor Accept-negotiation
**BC**: ActivityPub Federation
**Files**: `crates/solid-pod-rs-activitypub/src/actor.rs`
**JSS ref**: commit `bfc37db`

- Add `negotiate_actor_format(accept_header: &str) -> ActorFormat` enum
- When Accept contains `application/activity+json` or `application/ld+json; profile="https://www.w3.org/ns/activitystreams"` → return AP JSON-LD
- Otherwise → return LDP Turtle/JSON-LD (existing)
- Tests: AP Accept → AP actor JSON, LDP Accept → LDP profile

#### 9. AP outbox delivery with follower fan-out
**BC**: ActivityPub Federation
**Files**: `crates/solid-pod-rs-activitypub/src/delivery.rs`, `src/store.rs`
**JSS ref**: `src/ap/routes/outbox.js:122-147`

- Add `get_follower_inboxes()` to `Store`
- `DeliveryWorker` accepts list of inboxes for fan-out
- Report delivery results (succeeded/failed counts) in response
- Tests: fan-out to 3 mock inboxes, partial failure handling

#### 10. AP store: actor cache datetime fix
**BC**: ActivityPub Federation
**Files**: `crates/solid-pod-rs-activitypub/src/store.rs`
**JSS ref**: commit `427a609`

- Verify our sqlx datetime columns use ISO 8601 format
- Add `cached_at` column to actors table if missing
- Test: actor cache insert + retrieval with timestamp

---

## Agent Assignment (Hierarchical Mesh)

```
                    ┌──────────────┐
                    │  Coordinator │
                    │  (this node) │
                    └──────┬───────┘
             ┌─────────────┼─────────────┐
             ▼             ▼             ▼
    ┌────────────┐ ┌──────────────┐ ┌────────────┐
    │  Security  │ │     IdP      │ │     AP     │
    │  Agent     │ │   Agent      │ │   Agent    │
    │ items 1-4  │ │  item 5      │ │ items 6-10 │
    └────────────┘ └──────────────┘ └────────────┘
```

### File Ownership (no conflicts)
- **Security agent**: `src/wac/parser.rs`, `src/multitenant.rs`, `src/security/ssrf.rs`, `src/security/dotfile.rs`, `src/config/schema.rs`
- **IdP agent**: `crates/solid-pod-rs-idp/src/credentials.rs`
- **AP agent**: `crates/solid-pod-rs-activitypub/src/{outbox,delivery,actor,store}.rs`

---

## Acceptance Criteria

1. All 10 items compile under `cargo check --workspace --all-features`
2. New tests pass (`cargo test --workspace` — targeting 850+ tests)
3. `cargo clippy --workspace --all-features -- -D warnings` clean
4. PARITY-CHECKLIST.md updated with 11 new rows (169–179)
5. Parity: ~98% strict (127/132 rows present/net-new)

---

## Out of Scope (Sprint 13)

- P3: Cloudflare `cf-visitor` header (row 177)
- P3: AP CLI/env config knobs (row 178)
- P3: HTML error page helper (row 179)
- ADR-057 LWS10 OIDC port tickets (7 items)
