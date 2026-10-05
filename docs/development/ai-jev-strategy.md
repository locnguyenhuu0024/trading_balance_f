# AI Jev Strategy Candidate Drafts

Jev assessment enriches generated support and resistance candidates with optional Typesafe scores. It is disabled by default. Candidate generation and the manual review/apply flow remain available when the provider is disabled or unavailable. Assessments never place or prepare orders.

## Backend setup

Use Python 3.12 and install the SDK in the same virtual environment used by the backend. Version `0.7.2` is the integration contract baseline for this adapter; this guide does not claim it is the newest SDK release or verify the version installed in a particular environment.

```sh
python3.12 -m pip install typesafe-sdk==0.7.2
```

Check the installed version and the adapter's required imports without making a provider call:

```sh
python3.12 -c 'import importlib.metadata as m, typesafe_sdk; assert m.version("typesafe-sdk") == "0.7.2"; assert all(hasattr(typesafe_sdk, n) for n in ("TypeSafeClient", "Score", "Noul", "RetryPolicy")); print("typesafe-sdk 0.7.2 imports OK")'
```

Create an API key in the [official Typesafe console](https://console.typesafe.ai/). The backend reads these five settings from the environment of its running process:

| Setting | Default | Accepted behavior |
| --- | --- | --- |
| `JEV_ENABLED` | `false` | Enabled only when the value is `true` (case-insensitive, surrounding whitespace ignored). |
| `TYPESAFE_API_KEY` | unset | Required when enabled. Keep the value in the deployment's user-owned secret store. |
| `TYPESAFE_DEFAULT_MODEL` | `jev-latest` | Missing, blank, or whitespace-only values use the default. Other values must be at most 128 characters and contain no control characters; invalid names produce `settings_invalid`. |
| `JEV_TIMEOUT_SECONDS` | `3` seconds | Parsed as a number and clamped to `0.05`–`10` seconds. Missing, blank, or invalid values use the default. |
| `JEV_MAX_CONCURRENCY` | `4` | Parsed as an integer and clamped to `1`–`8`. Missing, blank, or invalid values use the default. |

For a local zsh session, enter the key with terminal input hidden, then export the non-secret settings. The key is not part of the command text or its output:

```zsh
read -rs 'TYPESAFE_API_KEY?Typesafe API key: '
export TYPESAFE_API_KEY
printf '\n'
export JEV_ENABLED=true
export TYPESAFE_DEFAULT_MODEL=jev-latest
export JEV_TIMEOUT_SECONDS=3
export JEV_MAX_CONCURRENCY=4
```

Start or restart the backend with the existing launcher from that same shell so it inherits these values. For a container or service, configure the settings in the user-owned environment for the backend process and apply them through the existing deployment procedure. A host shell's environment does not automatically enter a container or service, and this adapter does not automatically load repository environment files. Docker captures env-file values when a container is created, so env changes require container recreation; image changes require a rebuild and recreation. `docker restart` alone applies neither change. See [Docker deployment](#docker-deployment) for the existing API and worker procedures. Keep deployment-specific environment changes in the established user-owned secret and process configuration; this guide does not prescribe edits to protected configuration files or invent a new launch command.

The adapter creates a worker-owned Typesafe client, makes one System One call per candidate, and sets the SDK retry policy to zero retries. Its SDK timeout is bounded by both the configured timeout and the remaining assessment deadline. The request has a 12-second admission/evaluation budget: work that cannot be admitted within that budget is marked `deadline_exceeded`, and results arriving at or after the deadline are treated as incomplete. Issued work is drained and clients are closed before the backend returns, so cleanup may extend request duration beyond 12 seconds if an SDK call runs past its timeout. No automatic order action follows an assessment.

Typesafe's [Python SDK guide](https://docs.typesafe.ai/sdk/python) and [synchronous client API](https://docs.typesafe.ai/sdk/python/api/clients/sync) describe the SDK interfaces. Do not enable request/response body logging to diagnose a provider call; the adapter intentionally discards provider exception details and its structured assessment log omits prompts, context bodies, and model names.

## Docker deployment

For the repository's Ubuntu Docker deployment, follow the existing [API rebuild and recreation procedure](../deployment/position-trade-api.md#rebuild-and-recreate-after-an-application-change). The Dockerfile and `/etc/trading-balance/trade-api.env` are user-owned deployment files. Install the SDK into the image as shown below; keep the API key in the server-side env file, never in the Dockerfile, image, or repository.

In the user-owned `backend/Dockerfile`, add this install step after the Python base image is selected and before the `USER` instruction:

```dockerfile
RUN python -m pip install --no-cache-dir typesafe-sdk==0.7.2
```

Add the five settings to the existing `/etc/trading-balance/trade-api.env` with `sudoedit`, retaining its other entries and replacing the API-key placeholder with the key from the user-owned secret store:

```sh
sudoedit /etc/trading-balance/trade-api.env
```

```text
JEV_ENABLED=true
TYPESAFE_API_KEY=<SET_BY_USER>
TYPESAFE_DEFAULT_MODEL=jev-latest
JEV_TIMEOUT_SECONDS=3
JEV_MAX_CONCURRENCY=4
```

Build the image from the repository root:

```sh
sudo docker build -f backend/Dockerfile -t trading-balance-trade-api .
```

Recreate the API container with the existing deployment's full `docker run` recipe, including its protected `--env-file` option, read-only filesystem, security options, database bind mount, and loopback-only port mapping. The exact API-only recipe is in the [deployment guide](../deployment/position-trade-api.md#ubuntu-2404-lts-container); if the separate strategy worker is deployed, use the [coordinated API and worker image procedure](../deployment/position-trade-api.md#strategy-order-monitor-worker). A plain `docker restart` reuses the current container and does not apply a rebuilt image or changed env-file values. Recreate the worker from the same image as part of the coordinated procedure when it is deployed.

After recreation, check the SDK version and imports inside the API container without making a provider call or reading the key:

```sh
sudo docker exec trading-balance-trade-api python -c 'import importlib.metadata as m, typesafe_sdk; assert m.version("typesafe-sdk") == "0.7.2"; assert all(hasattr(typesafe_sdk, n) for n in ("TypeSafeClient", "Score", "Noul", "RetryPolicy")); print("typesafe-sdk 0.7.2 imports OK")'
```

If the strategy worker container is present, run the same check against `trading-balance-strategy-worker`. Then use the manual Strategy validation below; only a new Draft with at least one non-empty successful assessment verifies the SDK and API key together. Docker's [container run reference](https://docs.docker.com/reference/cli/docker/container/run/) and [build best practices](https://docs.docker.com/build/building/best-practices/) document the container environment and image build behavior.

## Manual validation

1. Open the Strategy screen, select the **Dựng chiến thuật tự động** action, choose a USDT swap instrument, and explicitly choose H6, D1, or W1 UTC candles.
2. Generate a new Draft and review its candidate status in the interface. In the saved Draft/API JSON, inspect `aiGeneration.supports[].assessment` and `aiGeneration.resistances[].assessment`: each assessment has a `status` of `success`, `disabled`, or `failed`. Successful saved assessments include `structuralQuality` (0–5), `entrySuitabilityProbability` (0–1), and `failureRiskProbability` (0–1). The saved JSON also records `modelRequested`, `modelUsed`, `evaluatedAt`, `errorCode`, and `contextHash`; these are assessment metadata and are not implied to be displayed in the interface.
3. Confirm the result remains a candidate Draft for manual review and selection. Assessment status and ranking do not submit, size, or prepare an order.

Treat the SDK and API key as verified only after a request produces at least one candidate with a non-empty `success` assessment. This documentation change did not perform live SDK or key verification. If generation produces no candidates, the SDK is not invoked, so an empty candidate list does not verify SDK installation, API-key validity, or provider connectivity.

Each generation request includes a `requestId` of 8–64 letters, digits, underscores, or hyphens. Repeating the same request ID with the same instrument and timeframe replays the saved result; using that ID for different inputs returns a conflict. Candidate Drafts are immutable snapshots. To apply changed provider settings or obtain a fresh assessment, submit a new generation request with a new request ID and review its new Draft.

## Troubleshooting and rollback

Use the saved candidate's fixed `errorCode` to identify the failure category:

| Code | Meaning / next check |
| --- | --- |
| `disabled` | `JEV_ENABLED` is not `true`. |
| `key_missing` | The enabled backend process did not receive `TYPESAFE_API_KEY`. |
| `sdk_unavailable` | The backend interpreter cannot import the expected SDK interface; check the version and import check above in that interpreter. |
| `settings_invalid` | The requested model setting is invalid. |
| `provider_unavailable` | Client construction or context entry failed; check the process environment and provider availability through the deployment's normal operational process. |
| `provider_error` | The provider operation failed. The code does not identify a particular HTTP status. |
| `timeout` | An individual SDK operation exceeded its effective timeout. |
| `deadline_exceeded` | The operation could not be admitted or completed within the overall assessment budget. |
| `invalid_model` | The response did not contain an acceptable model name. |
| `invalid_response` | The response was missing required fields or contained values outside the expected ranges. |

For an offline regression check, run the automatic strategy tests, which use mocked provider and exchange transports:

```sh
python3.12 -m unittest backend.tests.test_strategy_automatic -q
```

To disable Jev assessment, set `JEV_ENABLED=false` in the backend process environment and restart the backend through its existing launcher or deployment procedure. For Docker, edit the user-owned env file and recreate the container so it receives the changed value; `docker restart` alone does not reload env-file changes. Saved candidate metadata remains available for review.
