# Task 12: Add APK Release Build

**Status:** Completed; checklist locked
**Canonical plan:** [`../docs/agents/plans/2026-09-05-add-apk-release-build.md`](../docs/agents/plans/2026-09-05-add-apk-release-build.md)

## Approval Gate

- [x] User explicitly authorizes execution of this plan and checklist.

## Checklist

- [x] Add a concurrent Android APK release build and its artifact path to `release_build.sh`.
- [x] Include the APK process in cleanup, completion waiting, and the Vercel deployment failure gate.
- [x] Validate shell syntax and run a standalone APK release build without triggering Vercel deployment.
- [x] Review the final diff, update this checklist, and report the result without committing or pushing.

## Completion Lock

All checklist items are complete. This task file is immutable; follow-up scope requires a new task checklist.
