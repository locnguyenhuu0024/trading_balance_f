# AI Jev Strategy Candidate Drafts

Jev assessment is disabled by default. Candidate generation and the existing manual review/apply flow remain available when the optional provider is disabled or unavailable.

## User-owned provider setup

Install the verified SDK version into the Python environment used to run the backend:

```sh
python3.12 -m pip install typesafe-sdk==0.7.2
```

Set these values in the backend process environment. Keep the API key in the user-owned secret store for the deployment environment; do not place it in the repository:

```text
JEV_ENABLED=true
TYPESAFE_API_KEY=<SET_BY_USER>
TYPESAFE_DEFAULT_MODEL=jev-latest
JEV_TIMEOUT_SECONDS=3
JEV_MAX_CONCURRENCY=4
```

Restart the backend process after installing the SDK and setting its environment. `JEV_TIMEOUT_SECONDS` is bounded to 10 seconds and `JEV_MAX_CONCURRENCY` is bounded to 8. The default values are 3 seconds and 4 workers. The feature makes one System One request per generated level, with no retries and a 12-second overall assessment admission/evaluation budget. Calls that return at or after that deadline are recorded as incomplete. The backend drains issued calls and closes their clients before returning, so cleanup can make the request take longer than 12 seconds if an SDK call runs past its timeout.

## Verification and safety

Normal tests inject a mocked provider and exchange transport. They do not contact Typesafe or OKX. A live provider check requires the user-owned SDK installation and API key; this repository change does not perform that check. Level inputs come from public market data, with read-only account-binding checks to keep saved drafts scoped to the authenticated exchange account. Generation sends no exchange mutations. It persists review candidates without order sizing, reservations, leverage changes, order preparation, or order submission. Every candidate remains reviewable if assessment is disabled or fails.

No environment, package, runtime, or deployment configuration file is changed by this feature. Disable assessments by setting `JEV_ENABLED=false` and restarting the backend; saved candidate metadata remains available for review.
