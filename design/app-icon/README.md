# App icon

`storage-cleaner-icon-v14.svg` is the source artwork. The app icon sizes in
`Spacera/Resources/Assets.xcassets/AppIcon.appiconset` are generated from it, using Apple's macOS
template: an 824×824 rounded square centred on a 1024×1024 canvas, with a soft shadow.

To regenerate them after changing the artwork:

```sh
swiftc -O -o /tmp/make-app-icon design/app-icon/make-app-icon.swift
/tmp/make-app-icon design/app-icon/storage-cleaner-icon-v14.svg Spacera/Resources/Assets.xcassets/AppIcon.appiconset
```

These files live outside `Spacera/`, so they aren't bundled into the app.
