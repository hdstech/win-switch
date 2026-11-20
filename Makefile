APP := WinSwitch.app
BIN := .build/release/WinSwitch
ZIP := WinSwitch.zip

# Signing identity preference order:
#   Developer ID Application (distributes + notarizes) >
#   Apple Development (paid-account dev cert) >
#   "WinSwitch Dev" (self-signed, keeps TCC stable locally) >
#   ad-hoc (fallback; TCC is revoked on every rebuild)
# Override explicitly with: make app SIGN_ID="Developer ID Application: You (TEAMID)"
SIGN_ID ?= $(shell security find-identity -v -p codesigning 2>/dev/null \
	| sed -n 's/.*"\(.*\)"/\1/p' \
	| grep -E "Developer ID Application|Apple Development|WinSwitch Dev" | head -1)

# Keychain profile for notarization. Create once with:
#   xcrun notarytool store-credentials winswitch-notary \
#       --apple-id you@apple.com --team-id TEAMID --password <app-specific-password>
NOTARY_PROFILE ?= winswitch-notary

.PHONY: all app run install icon notarize dist clean

all: app

app: $(BIN)
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$(BIN)" "$(APP)/Contents/MacOS/WinSwitch"
	cp Info.plist "$(APP)/Contents/Info.plist"
	cp Assets/WinSwitch.icns "$(APP)/Contents/Resources/" 2>/dev/null || true
	@if [ -n "$(SIGN_ID)" ]; then \
		echo "Signing with: $(SIGN_ID)"; \
		codesign --force --deep --sign "$(SIGN_ID)" \
			--identifier com.local.winswitch --options runtime "$(APP)"; \
	else \
		echo "Signing ad-hoc (no identity found; permissions won't persist)"; \
		codesign --force --deep --sign - "$(APP)"; \
	fi

$(BIN):
	swift build -c release

# Regenerate Assets/WinSwitch.icns from tools/make_icon.swift
icon:
	swift tools/make_icon.swift .iconbuild
	iconutil -c icns .iconbuild/icon.iconset -o Assets/WinSwitch.icns
	rm -rf .iconbuild

run: app
	open "$(APP)"

# Install to /Applications and launch from there. Removes the project copy.
install: app
	-pkill -f "$(APP)/Contents/MacOS/WinSwitch" || true
	ditto "$(APP)" /Applications/"$(APP)"
	rm -rf "$(APP)"
	open /Applications/"$(APP)"

# Notarize and staple the ticket for Gatekeeper-free distribution.
notarize: app
	ditto -c -k --keepParent "$(APP)" "$(ZIP)"
	xcrun notarytool submit "$(ZIP)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(APP)"
	@echo "Notarized. Distribute $(APP) (or rezip after stapling)."

# Rezip the stapled app for a GitHub release.
dist: notarize
	ditto -c -k --keepParent "$(APP)" "$(ZIP)"
	@echo "Upload $(ZIP) to your GitHub release."

clean:
	rm -rf .build "$(APP)" "$(ZIP)"
