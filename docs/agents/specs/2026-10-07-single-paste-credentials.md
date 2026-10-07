# Design Specification: Single-paste OKX Credentials

Status: READY_FOR_PLAN
Date: 2026-10-07
Tier: M
Decision Ledger: decisions recorded here; no unresolved material questions.

## Objective and Current State
Enter the complete credential bundle once and reuse existing local persistence.
OBS-001: `SettingsTradeAccessPage` always renders three fields, loads their saved values, and calls `SecureStorageHelper.saveOkxCredentials`.
OBS-002: the helper already persists three keys and broadcasts credential mutation. No persistence/API change is needed.
User approved the proposed bulk-paste/save/reuse behavior and explicitly requested planning and immediate implementation in this chat. This direct authorization governs execution without a second approval gate.

## Requirements and Acceptance
- REQ-001 / AC-001: default editor has one masked multiline paste field. Accept exactly three labeled lines, e.g. `API Key: demo-api`, `Secret Key: demo-secret`, `Passphrase: demo-pass`, or JSON object with `apiKey`, `secretKey`, `passphrase`. JSON and line aliases normalize label case, spaces, underscores and hyphens. API key aliases: apiKey; secret aliases: secretKey, secret; passphrase alias: passphrase. Trim values, preserve interior characters. Line values split at the first colon or equals only. Ignore blank lines. Reject unknown labels, duplicate semantic labels, missing fields, non-string JSON values, invalid JSON, extra text and whitespace-only values. Reject ambiguous/unlabeled values instead of guessing. Generic Vietnamese errors must never echo submitted input.
- REQ-002 / AC-002: offer an explicit manual mode with the existing three required fields. Validate trimmed non-empty values. Switching modes clears unsaved inputs so no hidden stale values can be saved. Neither mode saves until the user presses save.
- REQ-003 / AC-003: after all three stored values load as non-empty, show `Đã lưu thông tin API trên thiết bị` and `Thay đổi key`; do not claim connection verification. Reopening the page preserves this state. Replacement starts blank and has Cancel returning to saved state without a write. Incomplete saved credentials show the editor. Loading disables edits/save until resolved, avoiding stale hydration overwriting user input. Generic load error offers retry and prevents writes until retry succeeds.
- REQ-004 / AC-004: await existing save; only success clears controllers and collapses the editor. Save failure retains editor/input for retry and displays a generic error, never raw exceptions. Disable input/mode/change/cancel/save while save is pending. Disposal during async operations must be safe.
- REQ-005 / AC-005: preserve existing storage keys, mutation bus, read-only section and TradeSessionControls. No backend/auth/session/trading changes. No automatic clipboard access, logs of credentials, remote parsing, new dependencies or configuration edits.

## Design, Invariants, and Failure Semantics
Pure parser in `lib/features/settings/domain/okx_credential_bundle.dart` -> page validation -> existing helper -> saved summary. Parsing has no side effects. Editor/load/save state lives on the page. Sensitive text stays obscured with suggestions/autocorrect disabled and is cleared after successful persistence or cancel; dispose all controllers. Use existing theme primitives. Do not show secret values in the summary. Explain that storage applies to the current device/browser; do not promise cross-device sync or stronger platform security than existing storage provides.
Review resolution: Flutter SDK `EditableText` always prepends a newline-removing formatter at maxLines 1, while obscureText forbids multiline rendering. Use an obscured single-line field and an explicit `Dán từ clipboard` button. Only that user action reads Clipboard.getData and assigns the complete string directly to its controller, preserving newlines without passing through the single-line platform formatter. No background clipboard reads. Disable paste while pending; clipboard empty/unavailable returns a generic message and retains existing unsaved input. Verify actual button/channel paste, including multiline content, via widget test; controller assignment alone is insufficient. Keep normal JSON single-line entry and manual mode. Provide concise instructions to use the paste button for the three-line format, plus only synthetic format examples. For JSON use a strict flat string-object token reader (decode each quoted token with dart:convert) that retains every original key before normalization; ordinary map-only jsonDecode loses identical duplicate keys and is insufficient. No new dependency. Cancel preserves persisted keys before a save attempt; no rollback promise after a failed multi-key write.
Malformed/partial input: error and zero writes. Load failure: retry and zero writes. Save failure: generic error and remain editing, no false saved state. Existing helper's multi-key writes are not atomic; this task does not redesign persistence or promise rollback on storage failure.
Public API, schema, permissions, performance, external configuration actions: unchanged / none.

## Verification and Traceability
RED-001: malformed/duplicate/missing paste rejects with zero persistence calls (REQ-001/004).
GREEN-001: valid labeled bundle and JSON produce exact values including delimiter-containing passphrase (REQ-001).
TEST-001: parser tests valid formats/aliases/delimiters and all rejection cases.
TEST-002: widget tests bulk save, manual fallback, existing saved summary/reopen, change/cancel, pending load/save, load/save errors, no secret echo (REQ-002..005).
Observe baseline regression failure before product implementation; final formal negative-path RED check precedes primary-success GREEN check, then related test files. Build Flutter web after final executable edits. No full-suite default.

## Compatibility, Rollout, and Completion
No new storage format, dependency, migration or deployment action. Release through ordinary app build. Rollback reverts page/parser changes and leaves existing saved keys usable.
Complete only after focused behavioral checks, successful final web build and coordinator diff/audit. Any required protected-config change blocks that branch for user action.
