# dashboard_operator

Tercen admin & manager dashboard, deployed as a Tercen client web app
(`WebAppOperator`). Specification: `sci/doc/admin-dashboard-spec.md`.

- **Admin dashboard** — platform operations: overview, tasks (with logs +
  cancel), workers, users. Requires the `admin` role.
- **Manager dashboard** — per-tenant usage analytics (spec §8; lands with the
  `UsageService` backend). Requires the `manager` role.

## How it runs

The app is pure static Flutter web, served by Tercen main at
`/_w3op/<operatorId>/` (no task, no container). Tercen's "Run App" launcher
passes a `?token=` query parameter; the app moves it to `sessionStorage`,
scrubs it from the URL, and uses it for all API calls. Authorization is
enforced server-side — the UI role gate is cosmetic.

## Development

```bash
# against a local Tercen dev instance
flutter run -d chrome \
  --dart-define=DEV=true \
  --dart-define=TERCEN_URL=http://127.0.0.1:5400 \
  --dart-define=TERCEN_TOKEN=<token>
```

`pubspec_overrides.yaml` (gitignored) can point `sci_tercen_client` at a local
checkout:

```yaml
dependency_overrides:
  sci_tercen_client:
    path: ../sci_tercen_client/sci_tercen_client
```

## Release

CI builds `flutter build web` and commits `build/web` (the `serve` directory in
`operator.json`), then tags. Install into a domain's `library` team via
`CreateGitOperatorTask` (tercenctl / MCP `install_operator`) — once per domain.
