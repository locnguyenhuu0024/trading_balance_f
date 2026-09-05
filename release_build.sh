#!/usr/bin/env bash

set -Eeuo pipefail

readonly project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly web_output_dir="$project_root/build/web"
readonly macos_output_dir="$project_root/build/macos/Build/Products/Release"
readonly apk_output_path="$project_root/build/app/outputs/flutter-apk/app-release.apk"

web_pid=""
macos_pid=""
apk_pid=""

cleanup_children() {
  local status=$?

  trap - EXIT INT TERM

  for pid in "$web_pid" "$macos_pid" "$apk_pid"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done

  exit "$status"
}

require_command() {
  local command_name=$1

  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$command_name" >&2
    exit 1
  fi
}

trap cleanup_children EXIT INT TERM

require_command flutter
require_command npx

cd "$project_root"

printf 'Resolving Flutter dependencies...\n'
flutter pub get

printf 'Building web, macOS, and Android APK release artifacts in parallel...\n'
flutter build web --release --no-pub &
web_pid=$!
flutter build macos --release --no-pub &
macos_pid=$!
flutter build apk --release --no-pub &
apk_pid=$!

web_status=0
macos_status=0
apk_status=0

if ! wait "$web_pid"; then
  web_status=1
fi
web_pid=""

if ! wait "$macos_pid"; then
  macos_status=1
fi
macos_pid=""

if ! wait "$apk_pid"; then
  apk_status=1
fi
apk_pid=""

if (( web_status != 0 || macos_status != 0 || apk_status != 0 )); then
  printf 'Release build failed; Vercel deployment was skipped.\n' >&2
  exit 1
fi

printf 'Deploying the web release to Vercel production...\n'
npx --yes vercel@latest deploy --cwd "$web_output_dir" --prod

printf 'Release completed successfully.\n'
printf 'Web artifact: %s\n' "$web_output_dir"
printf 'macOS artifact: %s\n' "$macos_output_dir"
printf 'Android APK artifact: %s\n' "$apk_output_path"
