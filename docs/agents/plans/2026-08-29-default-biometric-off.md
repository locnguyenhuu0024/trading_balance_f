# Default Biometric Authentication to Off

## Objective

Prevent a fresh installation or an installation without a saved biometric preference from entering the biometric prompt at launch. The user can still opt in later from Settings.

## Repository context

`SecureStorageHelper.getBiometricAuth()` and the web-specific `WebStorageHelper.getBiometricAuth()` both interpret a missing `BIO_AUTH` value as `true`. In `main()`, the fallback value is also `true` if preference loading fails. This sends Android users directly to `BiometricAuthScreen`, where the supplied screenshot shows `LocalAuthException(code noCredentialsSet)`.

## Scope

- Treat a missing `BIO_AUTH` value as disabled in native and web storage helpers.
- Set the startup fallback to disabled when preferences cannot be read.
- Preserve an explicit saved value of `BIO_AUTH=true`, so users who previously enabled biometrics remain opted in.
- Keep the Settings switch and its persistence behavior unchanged.
- Add regression coverage for the web storage default and explicit opt-in behavior.

## Non-goals

- Do not remove biometric authentication or the Settings control.
- Do not change Android biometric configuration or device credentials.
- Do not overwrite a user's explicit biometric preference.

## Implementation steps

1. Change the native and web `getBiometricAuth()` defaults to return `true` only for an explicit stored `true` value.
2. Change the `main()` preference-read fallback to `false`.
3. Add focused tests for an unset and explicit biometric preference using `WebStorageHelper`.
4. Format affected Dart files, run the focused test, static analysis, the complete test suite, and an Android debug build.

## Risks and compatibility

- Existing users who deliberately enabled biometrics continue to see the lock screen because their saved `true` value is preserved.
- Users without a saved value enter the app directly, resolving the failure mode in the screenshot without requiring device-level biometric enrollment.

## Acceptance criteria

- A missing `BIO_AUTH` value resolves to `false` on native and web startup paths.
- `BIO_AUTH=true` remains enabled.
- Preference-read errors no longer default to biometric authentication.
- The app compiles, tests pass, and Android debug build succeeds.
