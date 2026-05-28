# Safari Swipe

A macOS Safari extension for reviewing bookmarks one at a time. A slim bar appears at the top of every page showing the next bookmark — keep it or delete it.

## How it works

- A 44 px overlay bar appears at the top of every page with the current bookmark title and a count of remaining bookmarks
- **Keep** — skips the bookmark for 30 days, then re-queues it
- **Delete** — removes the bookmark immediately
- **✕** — dismisses the bar for the rest of the session without changing any bookmarks

## Requirements

- macOS 14.0 or later
- Xcode (for building)

## Build & install

```sh
# Generate the Xcode project (only needed once, or after changing extension source)
make generate

# Build and install to ~/Applications
make install

# Open the installed app so it registers with Safari
make run
```

After running the app, enable the extension in **Safari → Settings → Extensions → Safari Swipe**.

## Development

Edit the web extension source files in `extension/`:

| File | Purpose |
|---|---|
| `extension/background.js` | Service worker — bookmark state, keep/delete logic |
| `extension/content.js` | Injects the overlay bar into every page |
| `extension/manifest.json` | Extension manifest (Manifest V3) |

After editing, run `make generate` to copy the files into the Xcode project, then rebuild.

To regenerate the icon PNGs:

```sh
make icons
```

## Project structure

```
extension/          Web extension source (edit these)
SafariSwipe/        Generated Xcode project (do not edit directly)
generate_project.py Generates SafariSwipe/ from extension/ source
Makefile            Build targets
```

## Make targets

| Target | Description |
|---|---|
| `make build` | Build the app in Release mode |
| `make install` | Build and copy to `~/Applications` |
| `make run` | Open the installed app |
| `make generate` | Regenerate the Xcode project |
| `make icons` | Regenerate icon PNGs |
| `make clean` | Remove `.build/` artifacts |
