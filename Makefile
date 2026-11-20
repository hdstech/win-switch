APP := WinSwitch.app
BIN := .build/release/WinSwitch
# Prefer a real signing identity so TCC permissions persist across rebuilds
# (ad-hoc signing changes the cdhash every build, revoking grants).
SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(.*\)".*/\1/p' | head -1)

.PHONY: all app run clean

all: app

app: $(BIN)
	mkdir -p "$(APP)/Contents/MacOS"
	cp "$(BIN)" "$(APP)/Contents/MacOS/WinSwitch"
	cp Info.plist "$(APP)/Contents/Info.plist"
	@if [ -n "$(SIGN_ID)" ]; then \
		codesign --force --deep --sign "$(SIGN_ID)" --identifier com.local.winswitch --timestamp=none "$(APP)"; \
	else \
		codesign --force --deep --sign - "$(APP)"; \
	fi

$(BIN):
	swift build -c release

run: app
	open "$(APP)"

clean:
	rm -rf .build "$(APP)"
