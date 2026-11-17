# Notarization & Distribution Guide

## ParaDict release credentials on this Mac

The existing notarization profile is **`ParaDict-notary`** (case-sensitive), stored in the iCloud keychain. In Keychain Access, search for `notary`; its account is `com.apple.gke.notary.tool.saved-creds.ParaDict-notary`. Do not recreate credentials when this profile is available.

After running `script/archive_release.sh`, submit the generated ZIP with `xcrun notarytool submit <zip-path> --keychain-profile ParaDict-notary --wait`. Once accepted, staple the app inside the archive, verify it with `stapler validate` and `spctl`, and create a fresh ZIP from that stapled app for GitHub.

## Problem

Even after notarization, macOS Sequoia blocks the app — users must go to Privacy & Security settings to launch it. This is because:

- macOS Sequoia removed the right-click "Open" bypass entirely
- ZIP files can't be stapled (only the .app inside can be)
- Without stapling on the container, Gatekeeper is more aggressive

## Option 1: DMG Distribution (Recommended)

A properly notarized + stapled DMG gives users the friendly "Are you sure you want to open this?" dialog with an **Open** button, instead of the "cannot be opened" block.

### Prerequisites

#### Developer ID Certificates

You need a **"Developer ID Application"** certificate (not just "Apple Development"). Check if you already have one:

```bash
security find-identity -v -p codesigning
# Look for: "Developer ID Application: Your Name (TEAMID)"
```

If missing, you can either:

1. **Regenerate from your Apple Developer account** (preferred):
   - Go to https://developer.apple.com/account/resources/certificates/list
   - Create a new "Developer ID Application" certificate
   - Download and double-click to install in Keychain

2. **Restore from Time Machine backup** (if needed):
   - Certificates live in Keychain, so look for: `~/Library/Keychains/` and the System Keychain
   - The private key is what matters — if you generated the CSR on the old Mac, the private key is only on that machine (or its backup)
   - In Keychain Access: File > Import Items, then import the `.p12` file
   - **However**: if the certificate was created via your Apple Developer account, you can just revoke the old one and create a new one — the cert is tied to your account, not the machine. The machine only holds the private key.

**TL;DR on certificates**: Try regenerating from the developer portal first. Only dig into Time Machine if you have a specific reason to keep the old certificate (e.g., existing notarized builds you want to match).

#### Store Notarization Credentials

One-time setup so you don't have to pass credentials every time:

```bash
xcrun notarytool store-credentials "notary-profile" \
    --apple-id "your@email.com" \
    --team-id "YOURTEAMID" \
    --password "app-specific-password"
```

The password is an **app-specific password** generated at https://appleid.apple.com/account/manage → Sign-In and Security → App-Specific Passwords.

### Step-by-Step: Build → Notarize → DMG

#### 1. Archive in Xcode

```
Product > Archive
```

Or via command line:

```bash
xcodebuild -project ParaDict.xcodeproj -scheme ParaDict \
    -configuration Release archive \
    -archivePath build/ParaDict.xcarchive
```

#### 2. Export with Developer ID

**Xcode GUI (easiest path):**
- In Organizer, select the archive → Distribute App → Developer ID → Upload
- Xcode notarizes and staples automatically
- Export the notarized app

**Command line:**

```bash
# Export the archive
xcodebuild -exportArchive \
    -archivePath build/ParaDict.xcarchive \
    -exportOptionsPlist ExportOptions.plist \
    -exportPath build/export
```

You'll need an `ExportOptions.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>YOURTEAMID</string>
</dict>
</plist>
```

#### 3. Verify the signature and stapling

```bash
# Verify code signature
codesign --verify --deep --strict --verbose=2 build/export/ParaDict.app

# Verify Gatekeeper accepts it
spctl --assess --type execute --verbose build/export/ParaDict.app
# Expected: "accepted source=Notarized Developer ID"

# Verify staple is present
xcrun stapler validate build/export/ParaDict.app
# Expected: "The staple and target are valid."
```

If the app isn't stapled yet (e.g., you exported without uploading via Xcode):

```bash
# Notarize manually
ditto -c -k --keepParent build/export/ParaDict.app ParaDict-notarize.zip
xcrun notarytool submit ParaDict-notarize.zip \
    --keychain-profile "ParaDict-notary" --wait
rm ParaDict-notarize.zip

# Staple the .app
xcrun stapler staple build/export/ParaDict.app
```

#### 4. Create the DMG

```bash
# Create DMG from the stapled .app
hdiutil create -volname "ParaDict" \
    -srcfolder build/export/ParaDict.app \
    -ov -format UDZO \
    build/ParaDict.dmg
```

For a nicer DMG with a drag-to-Applications arrow, consider using [create-dmg](https://github.com/create-dmg/create-dmg):

```bash
brew install create-dmg

create-dmg \
    --volname "ParaDict" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "ParaDict.app" 150 190 \
    --app-drop-link 450 190 \
    build/ParaDict.dmg \
    build/export/ParaDict.app
```

#### 5. Notarize and staple the DMG itself

```bash
xcrun notarytool submit build/ParaDict.dmg \
    --keychain-profile "notary-profile" --wait

xcrun stapler staple build/ParaDict.dmg
```

#### 6. Final verification

```bash
# Verify the DMG
spctl --assess --type open --context context:primary-signature --verbose build/ParaDict.dmg

# Mount and verify the app inside
hdiutil attach build/ParaDict.dmg
spctl --assess --type execute --verbose "/Volumes/ParaDict/ParaDict.app"
hdiutil detach /Volumes/ParaDict
```

### What Users Should See After This

The **only** dialog should be:

> "ParaDict" is an app downloaded from the Internet. Are you sure you want to open it?
> **[Open]** [Cancel]

No trip to Privacy & Security required.

---

## Option 2: PKG Installer

A `.pkg` installer is an alternative that also supports stapling. Better for apps that need to install helpers, launch agents, or specific file locations. More "enterprise" feel.

### When to Prefer PKG Over DMG

- You need to run pre/post-install scripts (e.g., set up a launch agent)
- You want the app installed in a specific location
- Your audience expects an installer workflow (enterprise/IT users)

### Steps

#### 1. Build and sign the .app

Same as Option 1, steps 1-3.

#### 2. Create the PKG

```bash
# Create a component package
pkgbuild --root build/export \
    --identifier com.paradict.app \
    --version 1.0 \
    --install-location /Applications \
    build/ParaDict-component.pkg

# Create a distribution package (nicer installer UI)
productbuild --synthesize --package build/ParaDict-component.pkg \
    build/distribution.xml

# Build the final installer
productbuild --distribution build/distribution.xml \
    --package-path build \
    --sign "Developer ID Installer: Your Name (TEAMID)" \
    build/ParaDict.pkg

rm build/ParaDict-component.pkg build/distribution.xml
```

Note: PKG signing uses a **"Developer ID Installer"** certificate (different from "Developer ID Application"). Generate this from the developer portal if you don't have one.

#### 3. Notarize and staple the PKG

```bash
xcrun notarytool submit build/ParaDict.pkg \
    --keychain-profile "notary-profile" --wait

xcrun stapler staple build/ParaDict.pkg
```

#### 4. Verify

```bash
spctl --assess --type install --verbose build/ParaDict.pkg
xcrun stapler validate build/ParaDict.pkg
```

---

## Debugging Checklist

If things still don't work, run these diagnostics on the distributed artifact:

```bash
# What quarantine attributes are set?
xattr -l ParaDict.app

# Detailed signature info
codesign -d --verbose=4 ParaDict.app

# Check entitlements
codesign -d --entitlements :- ParaDict.app

# Verbose Gatekeeper assessment
spctl -a -vvv -t execute ParaDict.app

# Check notarization history
xcrun notarytool history --keychain-profile "ParaDict-notary"

# Get log for a specific submission
xcrun notarytool log <submission-id> --keychain-profile "ParaDict-notary"
```

### Common Pitfalls

| Problem | Cause | Fix |
|---------|-------|-----|
| "developer cannot be verified" | Not notarized, or notarized but not stapled and network check failed | Notarize + staple |
| "damaged and can't be opened" | Broken code signature (modified after signing, or zipped with `zip` instead of `ditto`) | Re-sign, use `ditto` for ZIP |
| Nested framework unsigned | SPM dependency not signed during archive | Use Xcode's archive flow which handles this; verify with `codesign --verify --deep` |
| ZIP can't be stapled | ZIPs don't support stapling | Switch to DMG |

### Important: Never Use `--deep` for Signing

`codesign --deep` is unreliable. Always sign nested components individually (Xcode's archive flow does this correctly).

### Important: Always Use `ditto` for ZIPs

```bash
# Correct
ditto -c -k --keepParent ParaDict.app ParaDict.zip

# Wrong — can break code signatures
zip -qr ParaDict.zip ParaDict.app
```
