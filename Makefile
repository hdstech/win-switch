APP := WinSwitch.app
BIN := .build/release/WinSwitch

.PHONY: all app run clean

all: app

app: $(BIN)
	mkdir -p "$(APP)/Contents/MacOS"
	cp "$(BIN)" "$(APP)/Contents/MacOS/WinSwitch"
	cp Info.plist "$(APP)/Contents/Info.plist"
	codesign --force --deep --sign - "$(APP)"

$(BIN):
	swift build -c release

run: app
	open "$(APP)"

clean:
	rm -rf .build "$(APP)"
