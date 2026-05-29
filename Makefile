APP     := Safari Cleaner
SCHEME  := Safari Cleaner
PROJECT := SafariCleaner/SafariCleaner.xcodeproj

BUILD       := build
DEV_APP     := $(BUILD)/Build/Products/Debug/$(APP).app
RELEASE_APP := $(BUILD)/Build/Products/Release/$(APP).app
DEST        := $(HOME)/Applications/$(APP).app

.PHONY: all generate icons build dev run publish install open close reinstall reinstall-open rebuild-open uninstall clean help

all: rebuild-open

# Regenerate the Xcode project from extension source files
generate:
	python3 generate_project.py

# Regenerate bookmark icon PNGs
icons:
	cd extension && python3 create_icons.py

# Auto-generate the project if it doesn't exist yet
$(PROJECT):
	python3 generate_project.py

# Build for dev (Debug). Don't open.
build: $(PROJECT)
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Debug \
		-derivedDataPath "$(BUILD)" \
		-quiet

# Just run the dev build.
dev run:
	open "$(DEV_APP)"

# Build for production. Don't install.
publish: $(PROJECT)
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Release \
		-derivedDataPath "$(BUILD)" \
		-quiet

# Build for production and install to ~/Applications.
install:
	$(MAKE) publish
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(DEST)"
	cp -r "$(RELEASE_APP)" "$(DEST)"
	@echo "Installed → $(DEST)"
	@echo ""
	@echo "Next steps:"
	@echo "  1. make open"
	@echo "  2. Safari → Settings → Advanced → enable 'Show features for web developers'"
	@echo "  3. Safari → Develop → Allow Unsigned Extensions  (required after every Safari restart)"
	@echo "  4. Safari → Settings → Extensions → enable Safari Swipe"

# Open production. Build and install if it doesn't exist.
open:
	@test -d "$(DEST)" || $(MAKE) install
	open "$(DEST)"

# Kill the app.
close:
	-killall "$(APP)"

# Build for production, close if open (no install, no open).
rebuild-open:
	$(MAKE) publish
	-killall "$(APP)"
	rm -rf "$(DEST)"

# Build for production, close if open, reinstall to ~/Applications, and open.
reinstall:
	$(MAKE) publish
	-killall "$(APP)"
	rm -rf "$(DEST)"
	mkdir -p "$(HOME)/Applications"
	cp -r "$(RELEASE_APP)" "$(DEST)"
	@echo "Reinstalled → $(DEST)"

reinstall-open:
	$(MAKE) reinstall
	open "$(DEST)"

# Close the app and remove it from Safari.
uninstall:
	$(MAKE) close
	-killall "Safari"
	rm -rf "$(DEST)"
	@echo "Uninstalled $(APP)"

# Remove all build artifacts and caches.
clean:
	rm -rf "$(BUILD)"

help:
	@echo "Targets:"
	@echo "  make build           Build for dev (Debug)"
	@echo "  make dev             Open the dev build"
	@echo "  make run             Open the dev build"
	@echo "  make publish         Build for production (Release)"
	@echo "  make install         Build and install to ~/Applications"
	@echo "  make open            Open production (build if needed)"
	@echo "  make close           Kill the app"
	@echo "  make reinstall-open  Build, reinstall, and open"
	@echo "  make uninstall       Remove from ~/Applications"
	@echo "  make generate        Regenerate Xcode project from extension sources"
	@echo "  make icons           Regenerate icon PNGs"
	@echo "  make clean           Remove all build artifacts and caches"
