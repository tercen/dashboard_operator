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
`test/version_test.dart` has a check that the two agree. **That check is
skipped for now:** the committed `build/web` predates WP11. It still serves
`0.1.0` and none of the WP11 features. It must be rebuilt before the next tag.
Step 2 below rebuilds it and step 3 lifts the skip. Until someone does that, a
clean `flutter test` says nothing about `version.json`.

### Why old installs must go

The user menu opens the Dashboard install whose library project was **created
most recently**, not the one with the highest version. Installing an older
tag after a newer one therefore makes the older one open. Whether pulling an
existing project to a new tag changes its creation date has not been checked,
so the procedure does not rely on it either way. An upgrade leaves exactly one
Dashboard install per domain, and that one is at the new tag.

### Procedure

1. **Bump the version** in `pubspec.yaml` (`version: X.Y.Z`, no build suffix).
   The tag is the same string.
2. **Build** with the Flutter version pinned in `.tool-versions` (3.35.4):
   `flutter build web --release`. Check that `build/web/version.json` shows
   `X.Y.Z`. With a different Flutter SDK, `pub get` rewrites `pubspec.lock`
   and the build output differs, so use the pinned SDK.
3. **Lift the version check.** If `test/version_test.dart` still has a `skip:`
   on the `build/web/version.json serves the pubspec version` test, delete
   three lines: the `skip:` line (a single line ending in `,`) and the two
   `//` comment lines directly above it. Leave the closing `);` in place.
   Run `flutter test test/version_test.dart`. It must run and pass, with no
   test skipped. Only now do `pubspec.yaml` and `version.json` agree.
4. **Prove it:** `flutter analyze` and `flutter test` are clean, with nothing
   skipped.
5. **Commit** the version bump, `build/web` and the test change together.
   `pubspec.lock` must be unchanged. If it changed, the build used the wrong
   SDK: go back to step 2.
6. **Tag** that commit `X.Y.Z` and push the branch and the tag.
7. **Pull one library project to the new tag.** Pull it on the instance
   (for example `https://tercen.example`), in the domain's `library` team.
   If that team has more than one Dashboard project, pick the one to keep and
   pull that one. Any of them will do, because step 8 removes the others.
8. **Delete every other Dashboard project, and its operator, in that team.**
   Decide by project, not by creation date or by version: keep only the
   project you pulled in step 7. Do not delete the operator that belongs to
   the project you kept.
9. **Check the user menu** opens the new install. Open the Dashboard from the
   user menu, replace the end of the URL with `version.json`
   (`/_w3op/<operatorId>/version.json`), and check that it shows `X.Y.Z`.

### First install

Install into a domain's `library` team once per domain, from this repository
at a tag.

**To be verified:** a bare git-operator install may create no library project.
If so, the user menu may report the Dashboard as "not installed" even though
the operator exists.
