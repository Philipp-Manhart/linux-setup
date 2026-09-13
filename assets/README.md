# Visual assets

Keep personal visual assets here so the setup repository has one predictable
place for wallpaper images, icons, and documentation screenshots.

| Directory | Purpose |
|---|---|
| `wallpapers/` | Images you want to use as desktop wallpapers. |
| `icons/` | Project or desktop icons. |
| `images/` | Other reusable images, such as documentation artwork. |

Use common, non-proprietary formats where possible: PNG, JPEG, WebP, or SVG.
For large binaries, track the files with Git LFS rather than committing them as
ordinary Git blobs.

## Set a wallpaper

Add an image under `assets/wallpapers/`, then run this from the linux-setup
checkout:

```bash
./linux-setup desktop wallpaper assets/wallpapers/my-wallpaper.jpg
```

The command accepts either an absolute image path or a path relative to this
repository. It sets both GNOME's light and dark wallpaper preferences. COSMIC
wallpaper settings are not automated yet, so choose the image in COSMIC's
desktop settings.
