# Android updates

Install the updater-enabled APK once. Then use Settings → App updates → Check for updates → Download update → Install update. Android requires permission to install updates from Streamify and a confirmation for every installation. Existing app data is retained.

After the build secrets are configured and repository variable `ANDROID_RELEASES_ENABLED` is set to `true`, Android changes pushed to the `test` branch trigger `.github/workflows/android-release.yml`. The workflow runs the build, unit tests and lint, then publishes a GitHub release with `Streamify.apk` and `update.json`. It can also be run manually from GitHub Actions. Code changes must be committed and pushed; uncommitted local changes are not released.

The app checks public releases in Joshua131313/streamify, selects the greatest Android version code, and verifies the downloaded size, SHA-256, package ID, version code and signing certificate before opening the Android installer. There is no GitHub credential in the app. No silent installations or background polling are performed.

GitHub Actions secrets:
- ANDROID_SIGNING_KEY_BASE64: existing Android testing keystore, base64 encoded. Keep this key backed up; replacing it breaks upgrades for installed apps.
- ANDROID_GOOGLE_SERVICES_JSON: existing Android Firebase SDK configuration.
- ANDROID_TMDB_API_KEY: catalog configuration used by the app.
- ANDROID_API_BASE_URL: optional sports backend.

This is the existing tester distribution, signed with its original debug identity. It is not a Play Store production release. Do not reset the workflow run counter or reuse an existing release tag. CI version codes start at 101 and increase with each workflow run. For a local build with a custom version, pass `-PappVersionCode=NUMBER -PappVersionName=NAME` to Gradle. The bootstrap build has code 2.

Do not commit keystores, local.properties, SDK configuration or APK binaries. APKs belong in GitHub Releases. A future Play Store distribution should use its own signing and update strategy.
