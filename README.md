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

## Release and upgrade

There is no CI. `build/web` (the `serve` directory in `operator.json`) is built
and committed by hand, and a release is a git tag on that commit.

The version lives in `pubspec.yaml`. `flutter build web` copies it into
`build/web/version.json`, which is what an install serves.
`test/version_test.dart` checks that the two agree.

### Why old installs must go

The user menu opens the Dashboard install whose library project was **created
most recently** — not the one with the highest version. Installing an older
tag after a newer one therefore makes the older one open. So an upgrade
leaves exactly one Dashboard install per domain: the new one.

### Procedure

1. **Bump the version** in `pubspec.yaml` (`version: X.Y.Z`, no build suffix).
   The tag is the same string.
2. **Build:** `flutter build web --release`. Check that
   `build/web/version.json` shows `X.Y.Z`.
3. **Prove it:** `flutter analyze` and `flutter test` are clean.
4. **Commit** the version bump together with `build/web`.
5. **Tag** that commit `X.Y.Z` and push the branch and the tag.
6. **Pull the library project to the new tag** on the instance
   (for example `https://tercen.example`), in the domain's `library` team.
7. **Delete older Dashboard projects and operators** in that team, so the new
   install is the only one (see above).
8. **Check the user menu** opens the new install: its `version.json`
   (`/_w3op/<operatorId>/version.json`) shows `X.Y.Z`.

### First install

Install into a domain's `library` team once per domain, from this repository
at a tag.

**To be verified:** a bare git-operator install may create no library project.
If so, the user menu may report the Dashboard as "not installed" even though
the operator exists.
