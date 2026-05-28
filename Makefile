APP     := Safari Swipe
SCHEME  := Safari Swipe
PROJECT := SafariSwipe/SafariSwipe.xcodeproj

BUILD   := build
PRODUCT := $(BUILD)/Build/Products/Release/$(APP).app
DEST    := $(HOME)/Applications/$(APP).app

.PHONY: all generate icons build install run clean help

all: build

# Regenerate the Xcode project from extension source files
generate:
	python3 generate_project.py

# Regenerate bookmark icon PNGs
icons:
	cd extension && python3 create_icons.py

# Auto-generate the project if it doesn't exist yet
$(PROJECT):
	python3 generate_project.py

# Build the app in Release mode (requires Xcode)
build: $(PROJECT)
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Release \
		-derivedDataPath "$(BUILD)" \
		-quiet

# Build and copy to ~/Applications
install: build
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(DEST)"
	cp -r "$(PRODUCT)" "$(DEST)"
	@echo "Installed → $(DEST)"
	@echo "Run: make run   then enable Safari Swipe in Safari → Settings → Extensions"

# Open the installed app
run:
	open "$(DEST)"

# Remove build artifacts
clean:
	rm -rf "$(BUILD)"

help:
	@echo "Targets:"
	@echo "  make build      Build the app (requires Xcode)"
	@echo "  make install    Build and install to ~/Applications"
	@echo "  make run        Open the installed app"
	@echo "  make generate   Regenerate Xcode project from extension sources"
	@echo "  make icons      Regenerate icon PNGs"
	@echo "  make clean      Remove build artifacts (.build/)"
