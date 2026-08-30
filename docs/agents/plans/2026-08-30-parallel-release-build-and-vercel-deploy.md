# Implementation Plan: Parallel Release Build and Vercel Deploy

**Date:** 2026-08-30  
**Status:** Implemented; verification passed

## Objective

Add a root-level Bash script that prepares dependencies once, builds the Flutter web and macOS release artifacts concurrently, and deploys the generated web directory to the Vercel production environment only after both builds succeed.

## Repository Context

- The project is a Flutter app and already includes `web/vercel.json`; Flutter copies that configuration into `build/web` during web builds.
- The existing README documents the manual sequence: `flutter build web --release`, then `cd build/web` and `npx vercel --prod`.
- No `.vercel` project link is currently present in the repository. The Vercel CLI can therefore prompt for authentication/project linking on the first deployment; the script must not suppress that interaction or embed credentials.

## Technical Approach

- Create `release_build.sh` at the repository root with `bash` strict mode and an absolute project-root resolver, so it can be invoked from any working directory.
- Check that `flutter` and `npx` are available; run `flutter pub get` once, then start `flutter build web --release --no-pub` and `flutter build macos --release --no-pub` as background jobs.
- Wait for both jobs even if one fails. Abort without deploying when either build fails.
- On success, run `npx --yes vercel@latest --cwd build/web --prod`; this uses the generated static output and its copied `vercel.json`, while allowing normal Vercel authentication/linking when required.
- Print the generated web directory and macOS release directory after successful completion. Do not clean, delete artifacts, persist tokens, or modify Vercel project settings.

## Affected Files

- `release_build.sh` (new executable shell script at repository root)
- `README.md` (one concise usage note, if it improves discoverability)

## Verification Strategy

- Shell syntax validation with `bash -n release_build.sh`.
- Static review verifies strict mode, child-process wait handling, deployment gate, and no secret interpolation.
- Run `flutter test` and `flutter analyze` for repository regression coverage.
- Do not execute the script or deploy while implementing: executing it would create a production deployment, which requires a deliberate operator run and Vercel authentication/project selection.

## Risks and Rollback

The script deliberately deploys with `--prod`, so invoking it can update the production domain. It prevents deployment if either build fails but cannot validate project selection before Vercel authentication/linking. Delete the new script and README note to roll back; it has no runtime application effect.

## Acceptance Criteria

1. One root-level command launches web and macOS release builds concurrently after a single dependency resolution.
2. Vercel production deployment runs only after both successful builds.
3. Failure of either build produces a non-zero exit and skips deployment.
4. The script uses no stored credentials and supports Vercel’s first-run interactive linking.
