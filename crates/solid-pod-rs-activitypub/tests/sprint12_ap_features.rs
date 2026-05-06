//! Sprint 12 parity: ActivityPub feature existence tests.
//!
//! Verifies that Sprint 12 AP deliverables exist at the type level:
//! - `negotiate_actor_format` returns `ActivityJson` for AP Accept headers
//! - `handle_outbox_post` exists (type check via import)

use solid_pod_rs_activitypub::actor::{negotiate_actor_format, ActorFormat};
// Type-level existence check: importing handle_outbox_post proves it
// exists in the public API surface.
use solid_pod_rs_activitypub::outbox::handle_outbox_post;

// =========================================================================
// negotiate_actor_format (row 176)
// =========================================================================

#[test]
fn negotiate_actor_format_returns_activity_json_for_ap_accept() {
    assert_eq!(
        negotiate_actor_format("application/activity+json"),
        ActorFormat::ActivityJson,
        "application/activity+json must negotiate to ActivityJson"
    );
}

#[test]
fn negotiate_actor_format_returns_activity_json_for_ld_json_with_profile() {
    assert_eq!(
        negotiate_actor_format(
            r#"application/ld+json; profile="https://www.w3.org/ns/activitystreams""#
        ),
        ActorFormat::ActivityJson,
        "ld+json with AS profile must negotiate to ActivityJson"
    );
}

#[test]
fn negotiate_actor_format_returns_ldp_for_html() {
    assert_eq!(
        negotiate_actor_format("text/html"),
        ActorFormat::LdpProfile,
        "text/html must negotiate to LdpProfile"
    );
}

#[test]
fn negotiate_actor_format_returns_ldp_for_empty() {
    assert_eq!(
        negotiate_actor_format(""),
        ActorFormat::LdpProfile,
        "empty Accept must negotiate to LdpProfile"
    );
}

#[test]
fn negotiate_actor_format_is_case_insensitive() {
    assert_eq!(
        negotiate_actor_format("Application/Activity+JSON"),
        ActorFormat::ActivityJson,
        "case-insensitive matching required"
    );
}

// =========================================================================
// handle_outbox_post type check (row 174)
// =========================================================================

/// This test verifies that `handle_outbox_post` is importable, proving
/// the function exists in the public API. We cannot invoke it here
/// because it requires a live `Store` + `Actor`; the import itself is
/// the assertion.
#[test]
fn handle_outbox_post_exists() {
    // The `use` import at the top of this file proves
    // `handle_outbox_post` is a public symbol. If the function were
    // removed or renamed, this file would fail to compile.
    //
    // We reference it here to suppress the unused-import warning.
    let _ = handle_outbox_post;
}
