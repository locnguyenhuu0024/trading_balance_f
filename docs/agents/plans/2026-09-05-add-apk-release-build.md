# Add APK Release Build

## Objective

Extend the root release script so one invocation builds Android's release APK alongside the existing web and macOS release artifacts, while retaining the current Vercel production deployment gate.

## Repository Context

`release_build.sh` currently resolves Flutter dependencies, starts web and macOS release builds in parallel, waits for both, and deploys the generated web artifact to Vercel only when both builds succeed.

## Scope

- Add `flutter build apk --release --no-pub` to the release build workflow.
- Run the Android APK build concurrently with the web and macOS builds.
- Track the APK process and include its result in the failure gate that prevents Vercel deployment.
- Print the release APK artifact path on successful completion.

## Non-goals

- Do not change Vercel configuration, deployment target, credentials, or deployment timing beyond gating it on the added build.
- Do not build an Android App Bundle, sign/publish an Android release, or modify Flutter dependencies.
- Do not modify application source code or existing completed task records.

## Implementation Steps

1. Define the release APK output path and add a process identifier/status for the APK build.
2. Launch `flutter build apk --release --no-pub` with the existing web and macOS release commands.
3. Extend cleanup and wait/failure handling to cover all three background builds; skip Vercel deployment if any build fails.
4. Report the APK artifact path with the existing web and macOS paths after a successful deployment.
5. Validate shell syntax and run `flutter build apk --release` independently. Do not execute the combined script because it performs a production Vercel deployment.
6. Review the final diff and mark the checklist complete.

## Risks and Compatibility

- Android tooling, SDK licenses, or signing configuration may be unavailable on the host; the separate APK build verification will reveal this.
- The script will take longer because it now waits for a third artifact, but parallel execution minimizes the added elapsed time.
- A failed APK build intentionally prevents Vercel deployment, ensuring the script represents an all-artifacts release workflow.

## Acceptance Criteria

- `release_build.sh` starts release builds for web, macOS, and APK concurrently after dependency resolution.
- A failure in any of the three builds exits non-zero and does not invoke Vercel.
- On success, the script deploys the web output as it does today and prints the APK path `build/app/outputs/flutter-apk/app-release.apk`.
- `bash -n release_build.sh` passes and a standalone `flutter build apk --release` completes successfully in the available environment.
