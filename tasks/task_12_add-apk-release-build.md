# Task 12: Add APK Release Build

**Status:** Planned
**Canonical plan:** [`../docs/agents/plans/2026-09-05-add-apk-release-build.md`](../docs/agents/plans/2026-09-05-add-apk-release-build.md)

## Approval Gate

- [ ] User explicitly authorizes execution of this plan and checklist.

## Checklist

- [ ] Add a concurrent Android APK release build and its artifact path to `release_build.sh`.
- [ ] Include the APK process in cleanup, completion waiting, and the Vercel deployment failure gate.
- [ ] Validate shell syntax and run a standalone APK release build without triggering Vercel deployment.
- [ ] Review the final diff, update this checklist, and report the result without committing or pushing.
