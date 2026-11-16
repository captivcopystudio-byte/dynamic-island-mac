APP := build/Dynamic Island.app

.PHONY: build app run install clean

build:
	swift build -c release

app:
	./scripts/build-app.sh

run: app
	-pkill -x DynamicIsland
	open "$(APP)"

install: app
	-pkill -x DynamicIsland
	rm -rf "/Applications/Dynamic Island.app"
	cp -R "$(APP)" /Applications/
	open "/Applications/Dynamic Island.app"

clean:
	rm -rf .build build
