# macOS release config

The update pipeline now expects one GitHub secret:

- `MACOS_RELEASE_CONFIG_BASE64`

This secret is the base64 encoding of a JSON document shaped like
`packaging/macos-release-config.template.json`.

Required fields:

- `appleTeamId`
- `developerIdCertificateP12Base64`
- `developerIdCertificatePassword`
- `appleNotaryKeyId`
- `appleNotaryApiKeyP8Base64`
- `sparklePublicEdKey`
- `sparklePrivateEdKey`

Optional fields:

- `appleCodesignIdentity`
- `appleNotaryIssuerId`

## Local release

```bash
export MACOS_RELEASE_CONFIG_BASE64="$(base64 < release-config.json | tr -d '\n')"
export CURRENT_PROJECT_VERSION_OVERRIDE=123
./packaging/release-macos-update.sh
```

Outputs:

- `build/release-assets/`
- `build/update-site/`
- `build/release-metadata.env`

## CI release

The workflow `.github/workflows/dev-release.yml` now:

1. Decodes the single release bundle.
2. Imports the Developer ID certificate.
3. Builds the signed app and DMG.
4. Notarizes and staples the DMG.
5. Generates the Sparkle appcast.
6. Publishes the GitHub release and Pages artifact.
