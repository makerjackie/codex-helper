# Release and notarization

Release builds are signed with a Developer ID Application certificate, submitted to Apple's notary service, stapled, and packaged in a signed/notarized DMG.

Requirements:

- Xcode and Xcode Command Line Tools
- a valid Developer ID Application identity
- a `notarytool` keychain profile
- GitHub CLI for publishing the finished files

```bash
SIGNING_IDENTITY="Developer ID Application: Company Name (TEAMID)" \
NOTARY_PROFILE="your-notary-profile" \
VERSION="0.6.0" \
./scripts/package-release.sh
```

The script verifies the app signature, submits and staples the app, builds and signs the DMG, submits and staples the DMG, runs Gatekeeper assessment, and writes a SHA-256 checksum under `dist/`.

Publish the resulting DMG and checksum:

```bash
gh release create v0.6.0 \
  dist/Codex-Helper-0.6.0.dmg \
  dist/Codex-Helper-0.6.0.dmg.sha256 \
  assets/poster-zh-v0.6.0.webp \
  --title "Codex Helper v0.6.0" \
  --generate-notes
```
