# folio

A native macOS markdown viewer and editor — clean typography, live rendering, and direct editing when you need it.

| View mode | Edit mode |
| --- | --- |
| ![View mode](screenshots/view-mode.png) | ![Edit mode](screenshots/edit-mode.png) |

## Why Folio

Folio opens Markdown as a rendered page. Use Read / Edit or ⌘E to put a caret into the same page. **Edit Source…** opens the complete Markdown document.

- Centered reading column with extra room for tables
- Syntax-highlighted code and offline LaTeX and Mermaid rendering
- In-place table cell editing and a grid for adding or removing rows and columns
- Document outline, Find, HTML and PDF export, and sharing
- Open the original file in Xcode, VS Code, or TextEdit

## Requirements

- macOS 14+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project (`brew install xcodegen`)

## Building

```
xcodegen generate
open Folio.xcodeproj
```

The project uses Xcode's synced folder groups, so new files added under `Folio/` show up in Xcode automatically — you only need to re-run `xcodegen generate` after changing `project.yml` itself (build settings, dependencies, and so on).

## Releasing

```
scripts/release.sh v0.1.0
```

Archives a Release build and packages it in a Developer ID signed DMG. Folio uses the Rolling Rabbits team, with the IDs com.rr.folio and com.rr.folio.QuickLook.

To publish, configure a Rolling Rabbits notarization credential with `asc auth` or set `FOLIO_NOTARY_PROFILE` to the team's notarytool keychain profile, then pass `--publish`. The script notarizes and staples the DMG before uploading it to GitHub.

---

Inspired by [Glance](https://glance.md/).
