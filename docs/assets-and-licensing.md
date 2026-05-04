# Assets And Licensing

The repository separates source-code licensing from visual asset licensing.

## Source Code

Source code, scripts, tests, and documentation are licensed under the MIT
License unless a file or folder says otherwise.

## App Icon

`Assets/AppIcon/AppIcon.png` is an original app icon generated for this project
with the built-in image generation tool. `Assets/AppIcon/AppIcon.icns` is
derived from that PNG by `Tools/generate-app-icon.sh`.

These two app icon files may be used in this repository and in release builds
of Global Pet Assistant. If a downstream project replaces the icon, it should
record the replacement asset's source and license here.

Generation prompt:

```text
Create a 1024x1024 macOS app icon for an open-source desktop pet assistant named Global Pet Assistant. Original design only, no copyrighted characters. Style: polished Apple-style Liquid Glass icon, rounded square silhouette, translucent glass panel, soft blue-teal to violet depth, a friendly abstract pet companion symbol made from simple geometric shapes: a small paw/star/chat-bubble hybrid mascot silhouette, not a real animal, not a known character. Clean centered composition, high contrast at small sizes, no text, no letters, no watermark, no UI mockup. Icon should look native on macOS 26, dimensional but simple, suitable for an app bundle icon.
```

`Assets/AppIcon/AppIcon.iconset/` is a generated intermediate and is ignored by
git.

## Pet Assets

Pet packages are not included in the repository license by default. Do not
commit third-party pet spritesheets or character art unless the asset's license
explicitly allows redistribution and that license is documented here.

Global Pet Assistant can render Codex-compatible pet packages directly. Users
can place compatible packages in:

```text
~/.global-pet-assistant/pets/<pet-name>/
```

or import an already installed local Codex pet with:

```bash
swift run petctl import-codex-pet <name>
```

The importer copies the local package into the app-owned pet folder. It does not
grant redistribution rights for that asset.

## Bundled Placeholder

`Sources/GlobalPetAssistant/Resources/SamplePets/placeholder/spritesheet.png`
is a deterministic generated placeholder used for testing and fallback
rendering. It is safe to redistribute with the source code.
