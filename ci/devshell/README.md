# Dev shell: a Flutter build box on GitHub Actions, driven from the Claude sandbox

Why: the Claude sandbox has no Dart/Flutter SDK and its network blocks pub.dev, storage.googleapis.com,
maven.google.com and gradle (policy 403). GitHub is reachable, so a short-lived Actions job acts as the compiler box.

How it works
- `client.sh start [branch]` pushes the branch `dev-shell` (an empty commit on top of `branch`, subject carries `seq=` and `ts=`). That triggers `.github/workflows/dev-shell.yml`.
- The job installs Flutter 3.22.0 (cached), runs `dprep` (the same Android-project preparation as build.yml, keep in sync), writes `out/ready.txt` to branch `shell-out`, then polls the branch `shell-in` every 4 s.
- `client.sh run 'cmd'` writes `cmd/NNNNNN.sh` to `shell-in` (single force-pushed commit). The job runs it in the repo checkout (timeout 900 s, `# timeout=N` first line overrides), publishes `out/NNNNNN.txt` (first line `seq= rc= secs=`; last 200 KB of output). Files left in `$DS_ART` are published under `art/NNNNNN/` (`client.sh art N`).
- Helpers on the box (PATH): `dsync [branch]` (fetch + hard reset to origin/<branch>, pub get if pubspec changed; keeps android/ and build caches), `dprep` (one-time).
- The session ends after 12 minutes without a command (`IDLE_MAX`), after 90 minutes (job timeout), on `client.sh stop`, or when a new `dev-shell` push cancels it (concurrency group).
- Typical loop: edit in the sandbox, push to merge-a ([skip ci] if CI is not wanted), `client.sh run 'dsync merge-a && flutter analyze lib'`.

Rules
- The repository is PUBLIC: every command and output is public. No secrets, no `env`, no `cat .git/config`. The job never references repository secrets; `GH_TOKEN` is removed from the environment of commands.
- GitHub's Actions terms limit use to building/testing the project in the repository: keep sessions short, stop when done.
- Not a replacement for the emulator probe in build.yml.

Local simulation: the scripts accept `DS_REMOTE` (any git URL), `DS_MAIN`, `DS_HOME`, `POLL`, `IDLE_MAX`, so the logic can be tested against a bare repo (done for v2.14.3 dev-shell, all paths passed).
