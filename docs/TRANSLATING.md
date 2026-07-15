# Translating the HiCarta manual

The manual (`docs/`) is bilingual, built with **MkDocs Material** and the
**mkdocs-static-i18n** plugin.

## How it is organized

```
docs/
  images/        shared screenshots (language-neutral)
  ja/            Japanese — the SOURCE you edit by hand
  en/            English  — GENERATED from ja/ (default language, site root /)
```

- Every page exists once per language at the **same relative path**, e.g.
  `docs/ja/usage.md` ↔ `docs/en/usage.md`.
- English is the default and is served at the site root (`/`); Japanese is at
  `/ja/`. A language switcher appears in the top-right of the header.
- Images live in `docs/images/` and are shared. Reference them from a page as
  `../images/overview.png`.

## Editing workflow

1. **Edit the Japanese page** under `docs/ja/` (this is the source of truth).
2. Ask Claude to **update the matching English page** under `docs/en/` from the
   Japanese version — same relative path. For example:
   *"Update the English usage page (docs/en/usage.md) to match the Japanese one."*
3. Commit and push. The GitHub Action rebuilds and publishes the site.

Keep the two files structurally parallel (same headings, tables, links, and code
blocks) so the switcher lands the reader on the equivalent section. Do not
translate file names, paths, commands, or code — only prose and headings.

## Adding a new page

1. Create `docs/ja/<name>.md` and `docs/en/<name>.md`.
2. Add it to `nav:` in `mkdocs.yml` using the **unprefixed** path
   (`- New page: <name>.md`).
3. Add the Japanese label under the `ja` locale's `nav_translations:` in
   `mkdocs.yml`.

## Build locally (optional)

```bash
pip install mkdocs-material mkdocs-static-i18n
mkdocs serve      # preview at http://127.0.0.1:8000
mkdocs build      # one-off build into site/
```

If a translation is missing, the plugin falls back to the default language (English),
so the site never breaks mid-translation.
