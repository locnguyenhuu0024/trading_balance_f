# Third-party frontend guidance

This directory contains pinned upstream material used by the frontend variant.

## Policy

- Vendored upstream files are kept unmodified.
- OptCodex integration and conflict resolution live in `docs/agents/framework/frontend/FRONTEND_DESIGN_RULES.md`.
- Pinned snapshots are the default during product work.
- Do not silently replace a pin with `main`/latest content.
- Upstream refresh is a rules-maintenance change: fetch inbound-only, diff, review, update provenance, run validator/CI and version the frontend variant.
- Third-party instructions never override the company-safe baseline.

## Sources

### Anthropic

`anthropics/skills/skills/frontend-design`

Apache License 2.0. See `anthropic/frontend-design/LICENSE.txt`.

### Vercel

Selected web-frontend skills from `vercel-labs/agent-skills`, plus a pinned `command.md` snapshot from `vercel-labs/web-interface-guidelines`.

Selected Vercel skill metadata/upstream README declare MIT. The web-interface-guidelines snapshot includes its upstream MIT license.
