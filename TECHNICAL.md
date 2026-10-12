# Telegrive technical overview

How Telegrive stores a drive in Telegram, how the app keeps it in step, and
how to build and work on it. The user-facing summary is in
[README.md](README.md); the design system is in [DESIGN.md](DESIGN.md).

- [Architecture](#architecture)
- [The drive in Telegram](#the-drive-in-telegram)
- [On the phone](#on-the-phone)
- [Transfers](#transfers)
- [Photo backup](#photo-backup)
- [Behaviour in detail](#behaviour-in-detail)
- [Known limits](#known-limits)
- [Project layout](#project-layout)
- [Development](#development)
- [Platform support and roadmap](#platform-support-and-roadmap)

## Architecture

```text
Telegram (source of truth)                    This phone
┌────────────────────────────────────┐  sync  ┌──────────────────────────────┐
│ private channel "Telegrive"         │ ─────▶ │ index (Drift / SQLite)       │
│  • drive message (pinned) tgdrive2  │ live + │  folders · files · parts     │
│  • folder messages        tgfolder2 │ catch- │  albums · offline · backup   │
│  • album messages         tgalbum2  │  up    │                              │
│  • file messages          tgfile2   │        │ transfer queue (persisted)   │
│  • later parts of splits  tgpart2   │ ◀───── │ waiting changes (outbox)     │
│  • copy of the index      tgindex2  │ changes│                              │
└────────────────────────────────────┘        └──────────────────────────────┘
```

Telegram is the source of truth. Every file, folder and album is a message
in one private channel, and each message carries everything needed to
rebuild the drive from Telegram alone. The phone keeps an index of the
channel for speed and offline use, writes every change to Telegram first,
and indexes what Telegram hands back.

The app is Flutter, talking to Telegram through TDLib (1.8.36, through
`handy_tdlib`) as an ordinary user account. Riverpod 3 holds state,
go_router navigates (the sign-in screens follow TDLib's authorization state
rather than being pushed by hand), and Drift keeps the index. TDLib types
stay inside `infrastructure/` and `features/*/data`.

## The drive in Telegram

### The channel, and how it is found

The drive is a private channel, titled **Telegrive**, that the account
created. Its first open makes it: Telegrive creates the channel with a
plain description, moves it to the Archive so it stays out of the chat
list, sets the app icon as its photo, then sends the **drive message** and
pins it silently.

The drive message is what marks a channel as a drive. To find the drive on
a phone, Telegrive:

1. Checks the channel this phone last used for the account, if any, and
   that the account still created it.
2. Otherwise searches the account's chats for channels titled Telegrive.
   If none qualifies, it loads the chat lists and checks every archived
   channel, which also finds a drive someone renamed.
3. Takes a candidate only if the account created it and the drive message
   is in it: the message pinned last, another pinned message, or, should
   it have come unpinned, one Telegram's search finds by its kind
   (`tgdrive2`). The channel's title and description are left to people.
4. Creates a new drive when nothing qualifies.

The phone remembers the drive message's id, and each open checks that one
message is still there, pinning it again if it came unpinned and sending a
new one only when Telegram answers that there is none, so a lookup that
fails never leaves two.

### Message kinds

| Kind | Message | Holds |
| --- | --- | --- |
| `tgdrive2` | Text, pinned | The drive itself: its id and where the copy of the index is |
| `tgfolder2` | Text | One folder |
| `tgalbum2` | Text | One album |
| `tgfile2` | Document | One file, or the first part of a split file |
| `tgpart2` | Document | A later part of a split file |
| `tgindex2` | Document | A copy of the index (`telegrive-index.json.gz`) |

The `2` is the version of the format. A later format that an older app
couldn't read would take a new kind.

### How a message reads

Each record has a part for people and a part for the app:

```text
Quarterly report.pdf                  ← bold: the name
#Invoices #starred                    ← tags, tappable in Telegram
Part 1 of 3                           ← notes
┃ Telegrive details                   ← quote, folded to three lines
┃ tgfile2;id=…;name=…;folder=…;…      ← spoiler: the details line
```

- **The first line**, in bold, is the name, shortened to 96 characters
  with an ellipsis. Folders start with 📁 and albums with 🖼.
- **The tags line** has the folder's hashtag (for a file, the folder it is
  in; for a folder, its own, then `· in #Parent`), `#starred` and
  `#trash` when they apply. TDLib makes them tappable on its own.
- **The notes line** says `Part n of N` on a split file's first part and
  `Small copy, the original follows` on a small copy.
- **The details line** sits in an expandable quote under the label
  "Telegrive details", and under a spoiler, so it takes at most three
  lines and reads as noise until tapped. It is the only line read back.

A caption keeps to 1024 characters, Telegram's limit without Premium, even
on Premium, so an edit after Premium lapses still fits. When it would run
over, the notes go first, then the tags, then the bold name is shortened;
the details line is never cut.

Only the details line is read back, so the human lines can change without
changing the format.

### The details line

```text
<kind>;<key>=<value>;<key>=<value>;…
```

- The line starts with the kind. The last line of a message that starts
  with a known kind is the one read.
- Fields are split by `;` and each splits at its first `=`. A key written
  twice keeps its last value.
- Values are written as they are, except for characters that would break
  the line or that Telegram would turn into a hashtag, mention or cashtag.
  Those are written as `%` and their UTF-8 bytes in hex: `%`, `;`, `#`,
  `@`, `$`, line breaks and other control characters, and the direction
  marks Telegram strips from text (U+200E, U+200F, U+2028–U+202E, U+0333,
  U+033F, U+030A, U+FEFF). In a list, `,` separates items and is escaped
  inside one.
- A field this version knows but can't read (`size=big`) is left out, and
  the record then stands or falls on whether it can do without it.

A file whose name is `Q3; 100% #final.pdf` is written
`name=Q3%3B 100%25 %23final.pdf`.

### Fields

Times are Unix epoch milliseconds. Sizes are bytes. Ids are described
under [Ids and numbers](#ids-and-numbers).

**`tgfile2`, a file**

| Field | Meaning |
| --- | --- |
| `id` | The file's id |
| `name` | Its name |
| `folder` | The id of the folder it is in; absent at the root |
| `type` | MIME type |
| `size` | Size of the whole file |
| `parts` | How many parts a split file has; absent when it is whole |
| `part` | Which part this message is, from 1; only on parts after the first, which carry it when the first part is gone |
| `star` | `1` when starred |
| `taken` | When a photo or video was taken |
| `trashed` | When it went to the trash |
| `albums` | Ids of the albums it is in, `,` between them |
| `length` | Length of a video or audio file, in seconds |
| `replacedby` | Id of the file that took its place, while Replace keeps it in the trash |
| `original` | Size of the original photo while this message holds a small copy of it |
| `added` | When it was added to the drive |
| `changed` | When it was last changed |

**`tgpart2`, a later part of a split file.** Written once, never edited.

| Field | Meaning |
| --- | --- |
| `file` | The id of the file it is part of |
| `part` | Which part it is, from 1; never 1 |
| `parts` | How many parts the file has |
| `size` | Size of the whole file |

**`tgfolder2`, a folder**

| Field | Meaning |
| --- | --- |
| `id` | The folder's id |
| `name` | Its name |
| `parent` | The id of the folder it is in; absent at the root |
| `star` | `1` when starred |
| `trashed` | When it went to the trash, with everything inside it |
| `added`, `changed` | When it was made and last changed |

**`tgalbum2`, an album.** Which files are in it is kept in each file's
`albums`, so a photo can be in several albums without being copied.

| Field | Meaning |
| --- | --- |
| `id` | The album's id |
| `name` | Its name |
| `added`, `changed` | When it was made and last changed |

**`tgdrive2`, the drive message**

| Field | Meaning |
| --- | --- |
| `id` | The drive's id |
| `index` | The number of the message holding the copy of the index, once there is one |
| `added` | When the drive was made |

**`tgindex2`, the copy of the index**

| Field | Meaning |
| --- | --- |
| `drive` | The id of the drive it is a copy of |
| `through` | The number of the newest message it covers |
| `files` | How many files it holds |
| `added` | When it was written |

A file's caption on Telegram, details unfolded:

```text
IMG_2041.HEIC
#Camera #starred
Telegrive details
tgfile2;id=9b2f6d0e-6c1a-4f8e-9d0b-6a2e3c4d5f60;name=IMG_2041.HEIC;folder=0d4c…;type=image/heic;size=3145728;star=1;taken=1759312800000;albums=a1b2c3d4e5f6;added=1759312860000;changed=1759312860000
```

### Ids and numbers

- **File, folder and drive ids** are random UUIDs (version 4), made on the
  phone when the item is first created. They never change, so a rename or
  a move edits one message and nothing that points at the item breaks.
  Files and folders point at each other by id (`folder`, `parent`,
  `file`), never by name.
- **Album ids** are 12 hexadecimal characters.
- **A file forwarded into the channel** without details has no id of its
  own, so the index calls it `tg` followed by TDLib's id for its message
  until it is filed; filing it writes details under that id.
- **Message numbers** (`index`, `through`, and the `msg` entries of the
  copy of the index) are Telegram's own numbers for the channel's
  messages: 1, 2, 3 and on, as in `t.me/c/<channel>/<number>`. TDLib's id
  for message number *n* is *n* × 2^20; the app converts between them
  (`MessageNumber`).

The numbers in a details line are sizes in bytes, times in Unix
milliseconds, `length` in seconds, `parts` and `part` as counts from 1,
and `star` as `1`.

### Folder tags

A folder's hashtag is made from its name, since Telegram ends a hashtag at
anything but a letter, digit or `_`: letters, digits, combining marks and
`_` stay, anything else becomes `_`, runs of `_` become one, and the tag
is cut at 48 characters. A name with no letter becomes `#folder_…`. So
`Tax returns 2026` is `#Tax_returns_2026`.

Tags are for people: the drive goes by ids. Two folders with the same name
share a tag, and a file takes a renamed folder's new tag the next time its
caption is written, so renaming a folder is still a single edit.

### Split files

Telegram caps a message at 2000 MiB, 4000 MiB with Premium (4000 or 8000
upload parts of 512 KiB). A bigger file is sent as 512 MiB parts, named
`movie.mkv.001`, `movie.mkv.002` and so on so they sort in Telegram.

Only the first part's caption says what the file is (`tgfile2`, with
`parts`). Each later part says only whose part it is (`tgpart2`) and is
never edited, so renaming, moving or starring a split file is one edit.
The index follows the first part. A later part read first makes a stand-in
row, named after the part's file name without its number, for the first
part to replace, so a full read in any order ends the same. A change to a
file whose first part is gone is written onto each part left, whole, and
then those count until a first part turns up.

Parts are much smaller than the cap on purpose: an interrupted upload only
loses the part in flight, and the temporary copy on the phone stays small.

### Forwards and adopted files

Media in the channel with no details line (a forward, or a file sent from
another Telegram app) is adopted: it shows at the root, under Forwarded,
with a made-up id. The plain text message sent just before a burst of
forwards is its comment. If it names a folder (`Wedding`, a path like
`Taxes/2026`, or `#Taxes/2026` to make what is missing), each file moves
there: Telegram copies it into a message of the drive's own, with details,
and the forward goes. The comment is deleted once every file it covered
has moved. Only forwards newer than the first read of the channel are
filed this way, so nothing already there moves on its own. Telegram won't
edit a forwarded message, which is why filing one copies it.

### The copy of the index

The channel also keeps a copy of the whole index: one document,
`telegrive-index.json.gz`, captioned `tgindex2`, which the drive message
points to by number. A phone opening a drive for the first time fills its
index from the copy and shows Home at once, then reads the channel in full
behind it and settles whatever changed since the copy was written.

The copy is a head start only; the captions stay what the drive is. A copy
that is missing, unreadable, of another format or of another drive is
passed over for the full read, and deleting it changes nothing but how
fast a new phone opens.

It is gzipped JSON, `format` 2:

```text
{ "format": 2,
  "folders": [ { id, p (parent), n (name), msg, ct, mt, tr, st, x } ],
  "albums":  [ { id, n, msg, ct, mt } ],
  "files":   [ { id, f (folder), n, m (type), s (size), ct, mt, pc (parts),
                 st, tk (taken), tr, x (fields a newer version wrote), du,
                 rb, ad (adopted), lt (original), al (album ids),
                 parts: [ { i (index from 0), msg, s } ] } ] }
```

`msg` is a message number. Nothing in it is particular to the phone that
wrote it: no previews and no TDLib file ids.

A copy is written after a full read of the channel, at most every three
days, and only when the index has changed since the last one (a
fingerprint of its contents says so). On a metered connection, mobile data
or a hotspot, only a copy of up to 1 MB goes; a few thousand files make a
few hundred kilobytes. Each copy replaces the document in the same
message, so the pointer never moves.

### Newer versions

Fields a newer version wrote that this one doesn't know are kept in the
index (`manifest_extra`, as JSON) and written back on every edit, first on
the line and under their own names, so a rename here never drops them. A
value goes back onto the line exactly as it came.

## On the phone

- **The index.** A Drift (SQLite) database of folders, files, their parts
  and albums, plus what belongs to this phone alone: offline copies,
  recently opened files, backup records, waiting changes. Browsing and
  search read only the index.
- **Changes go to Telegram first.** A rename, move, star, trash or album
  change edits the message, and the index is written from the message
  Telegram sends back, so it never claims something the channel doesn't
  have. Messages are sent silently, so nothing notifies.
- **Without a connection,** a change shows at once, waits on the phone
  (marked with a clock, listed under Waiting changes), and goes to
  Telegram in order when the connection is back. Each waiting change is a
  per-field patch: it is merged onto the message as Telegram has it by
  then, and a field another device changed meanwhile keeps that device's
  version, which you are told about.
- **Sync** runs live while the app is open (new, edited and deleted
  messages flow straight in), catches up incrementally on open and on
  pull-to-refresh, and reads the channel in full daily, once after an
  update that changes how messages are indexed (`MessageIndexer.version`),
  and from Settings › Rebuild index. A full read drops what the channel no
  longer has and empties what has been in the trash for 30 days.
- **Home before Telegram answers.** Each time the drive opens, the phone
  keeps the account's name and id and which channel holds the drive
  (never the phone number), and the next start shows Home from them and
  the index, once the channel has been read in full at least once.
- **The index belongs to one account.** Signing out wipes it with the sync
  checkpoints. A different account signing in wipes the previous one's
  index before its own drive opens. A session ended from Telegram closes
  the drive and keeps the index for seven days, so signing back in soon
  shows it at once. A drive found on a new channel has the old channel's
  index cleared before it is read.
- **Secrets.** The API credentials and TDLib's database key live in the
  platform keystore, and TDLib's cache is encrypted from the first launch.

## Transfers

- A queue that survives restarts, with live speed and ETA, pause, resume,
  cancel and retry. On Android a foreground service keeps it going in the
  background, and its notification can pause it.
- Split uploads resume at the last finished part; a send TDLib resumed on
  its own after a restart is matched by its caption.
- A dropped connection waits instead of failing, and a request that times
  out is tried again, up to three times in a row. Telegram's flood waits
  are counted down and sat out, and when Telegram turns one upload away
  the others hold off too.
- Before writing a big copy, a part or a download, the phone is checked
  for room; without it the transfer waits and says how much it needs.
- Starting 50 MB or more on mobile data asks first. Transfers of 200 MB or
  more started on Wi-Fi step back when the phone moves to mobile data (a
  setting, on by default). A hotspot counts as mobile data everywhere.
- Copies from other chats, and files sent from the drive to a chat, are
  forwards Telegram sends as copies, so nothing is downloaded or
  uploaded.

## Photo backup

- **Scope.** Every photo, and optionally every video, minus the device
  folders switched off. Folders that appear later are included.
  Screenshots and chat folders back up too but stay out of the Photos
  timeline until shown.
- **Where it goes.** `Photo backup › <device folder>`, originals in full
  quality as documents (Telegram would otherwise recompress them), with
  their capture time and GPS intact, a preview thumbnail so videos have
  posters, and each video's length.
- **Exactly once.** Each photo's device id is remembered, and anything
  already in the drive under the same name and size (after a reinstall, or
  from an old phone) is recognised and skipped. Backup waits for a full
  read of the channel before judging that.
- **Mobile data.** Don't use (the default), Photos only, or Photos and
  videos, and an optional monthly limit with the day the plan renews.
  Each photo or video is checked against what is left before it starts.
- **Small copies first.** With it on, a new photo that can't go up in full
  yet goes up as a JPEG of about 300 KB, carrying `original` with the
  original's size. On Wi-Fi, or within the limit, the original takes its
  place in the same message (`editMessageMedia`), keeping its name,
  folder, star, albums and trash. Only the phone that took a photo can
  send its original.
- **Nothing silently skipped.** A photo that fails is tried again; after
  three tries it is listed under Backup › Not backed up with the reason,
  to retry or skip.
- **The queue, live.** Tapping backup's line on Photos or Transfers opens
  the Backup queue. Waiting lists the uploads under way, each with how far
  it has got, then every photo still to go, newest first. A tap opens the
  phone's own copy full screen, to swipe through the rest, with Back up
  now. The cross skips a photo, and calls off its upload if one is under
  way. The photo keeps its failures and any small copy, and Undo puts it
  back as it was and sends it next. Backed up shows what this run of the
  app sent up, in the Photos grid with its selection bar, so photos can
  be trashed (the phone's copy too, if you like), put in albums or sent
  while the rest follow.
- **Notices gaps.** After every full read, the photos backed up from this
  phone are matched against the index, and any whose file is gone are
  counted, never sent again until you choose to.
- **Keeps going.** A pass runs when the drive opens, when the app returns
  to the foreground and when the photo library changes. A pass looks
  through the whole library once a day, after a change to what is backed
  up, or after a photo was deleted; otherwise only at photos added since
  the last pass that finished, so a library of thousands takes about a
  second.
- **With the app closed,** Android wakes a small job the moment new photos
  land (a MediaStore content trigger) and every few hours as a fallback.
  It posts "N new photos to back up". With Back up on its own turned on,
  it also asks Android to back them up the next time the phone is charging
  and on Wi-Fi: that job opens the drive this phone already knows (never
  searching for, creating or changing a channel), runs a pass for up to
  eight minutes, and hands Telegram back to the app if the app opens.
  Only one of the two runs TDLib at a time.
- **Other folders.** Any folder on the phone can be watched; each new file
  in it goes up once to Files › Auto upload, or a folder you choose, once
  it has been left alone for a minute. Android's folder picker grants
  access to that folder alone, so no storage permission is asked for.
- **Free up space** deletes the phone's copies of photos and videos that
  are safely in the drive, optionally keeping the last 30 or 90 days. A
  photo with only a small copy in the drive is never among them.

## Behaviour in detail

**Files and folders.** Create, rename, move and delete folders, with
breadcrumbs, list and grid views, and sorting by name, date, size or type.
Show in folder opens the folder a file is in and points it out. A name
already in a folder asks Replace, Keep both or Skip; Replace puts the old
file in the trash, marked as replaced, with Restore previous version in
the new file's Details. Folders can be starred and sit at the top of
Home. Long-press or Select puts labelled actions in a bar along the
bottom. Recent lists what you opened, shared or sent on this phone and
what you added.

**Trash and undo.** Deleting moves things to the trash for 30 days.
Moving, renaming, starring, album changes and restoring all offer Undo for
six seconds; deleting for good, emptying the trash and deleting an album
wait ten seconds, with Undo, before anything leaves Telegram. Photos the
phone still has can be deleted from the phone too, once Undo has had its
time.

**Photos.** A timeline grouped by month, with a scrubber that names the
month beside your finger, select-a-month, drag to select, pinch to change
the grid, albums, Favorites and Videos. The viewer flicks down to close
and up for Details, and plays videos in place. Thumbnails are fetched only
for what stops on screen, and decoded at the size they are shown; phones
with little memory start in Save memory.

**Search.** Words and dates narrow each other ("invoice march 2024",
"last week"). PDFs and text files are read on the phone so search finds
them by what they say; pages that are pictures are read with the phone's
own text recognition (from Play services). A document fetched only
to be read is deleted once it has been.

**Playback.** Video, music, call recordings and audiobooks stream as they
play, with seeking, even across a split file's parts; on mobile data only
a short stretch ahead is fetched. Speeds from 0.75× to 2×, hold for 2×,
skip steps that fit the length, resume where you stopped (on this phone),
and audio from a folder plays on to the next file. PDFs open page by page
without downloading the whole file.

**Space.** Space lists the biggest files, each top-level folder with
everything below it, and what the phone keeps: opened files, thumbnails,
offline copies, the index and Telegram's own records. Opened files are
trimmed daily to a tenth of the phone's storage or a third of what is
free, whichever is less, between 100 MB and 1 GB.

**Offline.** Files and folders can be kept on the phone; keeping a folder
says first how many files it holds and how big they are. New files in a
kept folder follow on their own.

**Telegram.** Files, folders and albums can be sent to any chat as copies
from the channel, with no upload. Files in any chat, Saved Messages or a
channel you only read can be saved into the drive the same way. A proxy
(MTProto or SOCKS5, pasted, typed or opened from a link) is offered where
Telegram isn't reachable.

**Android.** Share to Telegrive from any app, with recent folders as
direct share targets; scan a document or take a photo straight into a
folder; attach drive files in other apps through Android's file picker (a
read-only DocumentsProvider); app lock with the phone's fingerprint, face
or screen lock.

**Check my drive** says whether the channel is private and yours with no
auto-delete timer, when it was last read in full, which split files are
missing a part, whether every photo backed up from this phone is still
there, what in the trash goes soon, whether two-step verification is on
and when an unused account is deleted, with a fix beside each that has
one.

## Known limits

- Split files appear in Telegram as numbered parts, and only Telegrive
  joins them back.
- A video the phone's player can't decode, such as some MKV files, keeps
  its poster and offers Open with another app.
- A group in slow mode takes one message at a time, so sending files there
  delivers the first only, and says so.
- When Telegram asks for a pause longer than five minutes, Telegrive lets
  the phone sleep, so a transfer may wait until the app is next opened.
- Files you open, stream or download count toward the monthly data limit
  but are never held back by it.
- While the app is closed, the job that notices new photos doesn't know
  about the monthly limit.
- Saving a file to the phone needs room for it twice over for a moment.
- Signing out forgets saved proxies with the rest of Telegram's data.
- A watched folder sends each file once; a file changed after it went up
  isn't sent again, and one renamed on the phone looks new.
- Android's file picker shows the drive only while app lock is off, and a
  file that isn't on the phone comes down only while Telegrive runs.
- A change made without a connection stays on this phone until it reaches
  Telegram; signing out loses it, and says how many would go. Creating
  folders and albums, deleting an album and deleting for good need the
  connection.
- A small copy carries no location or camera details; the original that
  replaces it does.
- Where you stopped in a video is kept on this phone only.

## Project layout

```text
lib/
├── app/               # app root, router (phase-driven), shell, theme
├── core/              # config, formatting, file kinds, shared widgets
├── infrastructure/
│   ├── telegram/      # TDLib client, background receiver, which engine
│   │                  # owns TDLib, secure storage, message numbers
│   ├── database/      # Drift schema and queries (the index)
│   ├── network/       # whether the phone is online, and metered
│   └── storage/       # small preferences
└── features/
    ├── auth/          # welcome, phone, code, password, QR
    ├── setup/         # splash; find or create the drive channel
    ├── drive/         # the format (domain/), indexer, repository, sync,
    │                  # the copy of the index, the outbox
    ├── transfers/     # upload and download queue, background keep-alive
    ├── backup/        # photo backup and watched folders
    ├── checkup/       # Check my drive
    └── files/ home/ photos/ search/ settings/ viewer/ …
```

The format lives in `lib/features/drive/domain/`: `caption_text.dart` has
the caption layout, folder tags and the details line, and `manifest.dart`
has the records and the field names.

## Development

The app's Telegram API credentials live in the git-ignored
`lib/core/config/telegram_api.dart`. On a fresh clone, copy the template
and fill in an `api_id` and `api_hash` from
[my.telegram.org](https://my.telegram.org/apps) › API development tools:

```bash
cp lib/core/config/telegram_api.example.dart lib/core/config/telegram_api.dart
```

Then run it on an Android device or emulator:

```bash
flutter pub get
flutter run
```

On iOS, TDLib comes from the app itself: handy_tdlib ships no iOS build.
Before the first iOS build, with Xcode, CMake and gperf installed, run:

```bash
tool/build_tdlib_ios.sh
```

It builds the TDLib commit handy_tdlib was generated from, with OpenSSL,
for iPhones and for the simulator on Apple silicon, into
`ios/Frameworks/tdjson.xcframework`, which git ignores. Runner links and
embeds it, and `openTdLibrary()` loads it as `tdjson.framework/tdjson`.
When handy_tdlib moves to a new TDLib, set `TD_COMMIT` in the script to
match and run it again. Then `flutter run` on an iPhone as usual; a
release build (`flutter run --release`) keeps opening from the home screen
once it is unplugged.

Tests and generated code:

```bash
flutter test                         # unit, database and widget tests
dart run build_runner build          # after changing the Drift schema
flutter test tool/screenshots/screens_test.dart --update-goldens
flutter test tool/icon/icon_test.dart --update-goldens && dart run flutter_launcher_icons
```

The screenshot harness renders the signed-in screens with sample data, so
UI work doesn't need a Telegram account. Some screens show the time, so a
re-run differs from the stored images by a digit or two.

A schema version bump also dumps the new schema into `drift_schemas/` and
regenerates the helpers `test/migration_test.dart` checks upgrades with;
the two commands are at the top of that test.

## Platform support and roadmap

| Platform | Status |
| --- | --- |
| Android (arm64, armv7, x86, x86_64) | Supported |
| iOS (arm64, and the Apple silicon simulator) | Runs, with TDLib built by `tool/build_tdlib_ios.sh`. Photo backup runs while the app is open; the features below that need Android are off. |
| macOS | Not yet. |

- **Newer TDLib and 16 KB pages.** `handy_tdlib` bundles TDLib 1.8.36, whose
  binaries aren't 16 KB-page aligned, so Android 15+ devices with 16 KB
  pages run the app in compatibility mode. The plan is to vendor current
  `libtdjson` builds.
- **iOS**: backup in the background, a share extension, and the features
  that use Android's own channels: watched folders, the Google Photos
  import, the drive in the system file picker, and the scanner and camera.
- **macOS**, with a TDLib framework through the same FFI binding.
- **End-to-end encryption** of file contents and details, with a recovery
  passphrase.
