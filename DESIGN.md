# Telegrive design

## Product

**Register:** product, operate. A phone utility, Android first.

**Users:** people who keep their files and camera roll in their own
Telegram. Visits are short: find a file, check that backup is working,
upload something, free up the phone.

**Principles**

1. **Content is the interface.** Thumbnails, names and sizes carry the
   screen. Chrome stays quiet so they can.
2. **Calm by default.** Colour means something. The accent marks the one
   action or the live state; kind hues only say what a file is.
3. **Honest numbers.** Sizes, counts and dates use tabular figures and plain
   units, never a stat block.
4. **One obvious action per screen.**
5. **Say what happens.** Plain sentences. No slogans, no dash chains.

## Colour

Neutral, cool greys (not cream) with one blue accent. In the light theme
the accent is the mark's blue and success its green, each a shade deeper at
the same hue so text in them reads against white. The dark theme keeps
softer tints, since the mark's own colours glare on a dark screen.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `bg` | `#F6F7F9` | `#111317` | Screen background |
| `surface` | `#FFFFFF` | `#181B20` | Sheets, dialogs, raised rows |
| `surface-2` | `#EEF0F3` | `#20242A` | Fields, thumbnail slots, selected rows |
| `line` | `#E1E4E9` | `#2B3038` | 1px dividers and outlines |
| `text` | `#15171B` | `#ECEEF2` | Primary text |
| `text-2` | `#5A6170` | `#A3AAB6` | Secondary text, folders, icons |
| `text-3` | `#868D9A` | `#737B88` | Meta, placeholders |
| `accent` | `#1E6FE8` | `#8FA9FF` | Primary action, selection, progress |
| `accent-soft` | `#E6F0FF` | `#1F2A47` | Selected rows, the active nav item |
| `success` | `#08853F` | `#5CC48E` | Done states |
| `danger` | `#C23636` | `#FF8A80` | Destructive, failures |

Kind hues colour a file's glyph only, never a surface: image `#7353C9`,
video `#C4435F`, audio `#B86E0E`, document `#2A63CF`, archive `#A95A25`,
app `#2B8657`, other and folders use `text-2`.

## Type

**IBM Plex Sans** (400, 500, 600, 700), one family, hierarchy from size and
weight. Numbers that line up (sizes, counts, progress) use tabular figures.

| Role | Size / weight | Line |
| --- | --- | --- |
| Screen title | 24 / 600 | 30 |
| Section title | 17 / 600 | 24 |
| Row title | 15 / 500 | 20 |
| Body | 15 / 400 | 22 |
| Secondary | 14 / 400 | 20 |
| Meta | 13 / 400 | 18 |
| Label | 13 / 600 | 18 |
| Button | 15 / 600 | 20 |

Letter spacing stays at the font's default. Body text is never below 13.

## Mark

A paper plane folded into a drive: three rounded facets with open gaps
between them.

| Facet | Colour | Shading |
| --- | --- | --- |
| Wing (top) | `#0EBC5F` green | cools to `#7FD4FF` sky at its tail |
| Body (right) | `#FDCD06` yellow | brightens outward |
| Keel (left) | `#3085FE` blue | fades to `#7C9BFE` lavender at its tip |

The blue and the green are the light theme's accent and success; the
yellow and the shading belong to the mark alone, and the UI has no
gradients.

- The artwork is `tool/icon/source/telegrive.png`. `tool/icon` renders
  every picture of it from that file: the app's own copy for `BrandMark`
  (`assets/brand/mark.png`), the launcher icons, the notification icon and
  the channel photo.
- In the app it stands bare, with no tile. The launcher icon puts it on
  white; the channel photo uses a faint blue so Telegram's circle has an
  edge.
- As a one-colour silhouette (notification, themed icon) the gaps stay
  open.
- Never recoloured, outlined, or set on a coloured tile.

## Shape and depth

Radii: **6** thumbnails in rows, **10** controls (buttons, fields, chips,
tiles), **14** cards, **16** sheet and dialog tops. Nothing rounder.

No card shadows. Surfaces separate by tone and 1px `line`. Only sheets,
dialogs and the upload button float.

## Space

4-point grid: 4, 8, 12, 16, 20, 24, 32, 40. Screen gutter 20. Related items
sit 8 to 12 apart, separate groups 24 to 32.

## Motion

State changes 150 to 200 ms ease-out, page transitions 250 ms fades, progress
animates its value. No bounce, no pulsing, nothing moves on its own.

## Navigation

Three places: **Home**, **Files**, **Photos**. Transfers is something
happening, not a place, so it shows as a status line above the bar (and in
Home's Activity group) while it runs; its full list is one tap away.
Settings lives under the avatar on Home.

## Patterns

- **Rows over cards.** Lists are full-bleed rows with inset dividers. Cards
  exist only where a group is genuinely separate (a status panel).
- **Media slot.** Every row has a 44px slot: the real thumbnail for media,
  otherwise the kind glyph on `surface-2`.
- **Status line.** Backup and transfer state is a sentence plus a thin
  progress bar, placed where it applies, not a banner card.
- **Empty states** are a sentence and, when there is one, the action.

## Avoid

Taken from the Impeccable catalog and checked by hand, since its detector
reads web code:

- Gradients on surfaces or text, glass, glows, coloured side stripes.
- Hero metric blocks, identical card grids, icon tiles stacked above
  headings, pills above headings, greeting headers.
- Radii above 16, hairline-plus-shadow cards, cards inside cards.
- Crushed letter spacing, all-caps sentences, tiny text.
- Dash-chained copy and slogans ("unlimited, forever").
