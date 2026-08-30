# trading_balance_f

A new Flutter project.

## Release Build and Deployment

From the project root, run:

```bash
./release_build.sh
```

It resolves dependencies once, builds web and macOS release artifacts in
parallel, then deploys `build/web` to Vercel production only when both builds
succeed. The first deployment may prompt for Vercel authentication and project
linking; no credentials are stored by the script.
