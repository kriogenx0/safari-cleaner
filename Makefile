APP     := Safari Cleaner
SCHEME  := Safari Cleaner
PROJECT := SafariCleaner/SafariCleaner.xcodeproj

BUILD       := build
DEV_APP     := $(BUILD)/Build/Products/Debug/$(APP).app
RELEASE_APP := $(BUILD)/Build/Products/Release/$(APP).app
DEST        := $(HOME)/Applications/$(APP).app

.PHONY: all dev build open close install uninstall reinstall clean help

all: dev

# Build Debug and open.
dev:
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Debug \
		-derivedDataPath "$(BUILD)" \
		-quiet
	-killall "$(APP)" 2>/dev/null; true
	open "$(DEV_APP)"

# Build Release.
build:
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Release \
		-derivedDataPath "$(BUILD)" \
		-quiet

# Build Release and open.
open: build
	open "$(RELEASE_APP)"

# Kill the running app.
close:
	-killall "$(APP)"

# Build Release and install to ~/Applications.
install: build
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(DEST)"
	cp -r "$(RELEASE_APP)" "$(DEST)"
	open "$(DEST)"
	@echo "Installed → $(DEST)"

# Kill and remove from ~/Applications.
uninstall: close
	-rm -rf "$(DEST)"
	@echo "Uninstalled $(APP)"

# Uninstall then reinstall.
reinstall: uninstall install

# Remove build artifacts.
clean:
	rm -rf "$(BUILD)"

help:
	@echo "Targets:"
	@echo "  make dev        Build Debug and open"
	@echo "  make build      Build Release"
	@echo "  make open       Build Release and open"
	@echo "  make close      Kill the running app"
	@echo "  make install    Build Release, install to ~/Applications, and open"
	@echo "  make uninstall  Kill and remove from ~/Applications"
	@echo "  make reinstall  Uninstall then install"
	@echo "  make clean      Remove build artifacts"
