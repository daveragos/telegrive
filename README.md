# Telegrive

Your Telegram account as an unlimited drive, with automatic photo backup.
Telegrive stores files in a private Telegram channel on your own account
and gives you a proper file manager on top: folders, search, previews,
stars, a photo timeline, and uploads of any size. There is no Telegrive
server and no account to create — people just sign in with their Telegram
phone number.

<p>
<img src="tool/screenshots/out/home_light.png" width="23%" alt="Home">
<img src="tool/screenshots/out/files_list.png" width="23%" alt="Files">
<img src="tool/screenshots/out/photos.png" width="23%" alt="Photos">
<img src="tool/screenshots/out/backup_settings.png" width="23%" alt="Photo backup">
</p>

## Features

- **Unlimited storage.** Every file is a message in a private channel that
  Telegrive creates (or finds again) on your account.
- **Any size.** Telegram caps a message at 2000 MiB (4000 MiB with Premium).
  Bigger files are split into 512 MiB parts and joined back on download.
- **Photo backup.** Turn it on once and the whole camera roll goes up in
  full quality — then every new photo and video follows on its own. Choose
  device folders, videos on or off, and whether mobile data carries nothing,
  photos only, or photos and videos. A Photos tab
  shows your photos and videos as a timeline grouped by month, with a
  swipeable full-screen viewer: flick down to close it, or up for Details,
  which says when the photo was taken, which folder and albums it is in and
  whether it came from this phone, and opens it in Telegram. The viewer's
  bar says which photo of how many you are on and moves it to the trash,
  with Undo. Video tiles carry a play glyph on a band along the bottom with
  the clip's length, and a video in the viewer waits on its poster until
  you tap Play, then plays in place with sound; tap to pause, scrub along
  the bottom, or open the full player. Screenshots and chat folders back up
  too, but the timeline leaves them out until you tap Show. Long-press and drag
  to select a run of photos, pinch to change the grid, and keep albums (a
  photo can be in several without being copied), plus Favorites and Videos.
  On a long timeline a thin handle shows at the right edge while you
  scroll; drag it and the month beside your finger is named, and letting
  go puts that month at the top. Tapping a month's name selects or clears
  the whole month, and its circle fills while all of it is selected.
  Home opens with one line that says whether everything is backed up and in
  sync, and when that was last checked.
- **Free up space.** Delete the phone's copies of photos and videos that are
  safely backed up, keeping the last 30 or 90 days on the phone if you like;
  they stay in the drive. Photo backup's screen offers it, Show them lists
  exactly what goes, and Home says so when the phone runs low on space.
- **Check my drive.** Settings › Check my drive looks the drive over and
  says, one sentence per check, whether the channel is private and yours
  with no auto-delete timer, when the channel was last read in full, which
  split files are missing a part, whether every photo backed up from this
  phone is still in the drive, what in the trash goes for good within a
  week, and whether two-step verification is on and how long the account
  may sit unused before Telegram deletes it. What needs you comes first,
  with the fix beside it: Turn off, Make private, Read everything again,
  Delete parts, Back up again or Leave them out, Open Trash, Open Telegram
  and Change. Settings › Security names this session as Telegram's Devices
  list does and sets the inactive-account timer.
- **See where the space goes.** The storage total on Home, or Stored in
  Telegram in Settings, opens Space: the 50 biggest files, which you can
  select and move or put in the trash, each top-level folder with
  everything below it, files in no folder, and what the trash holds. Under
  On this phone it says in plain figures what Telegrive keeps here (opened
  files, thumbnails, copies left by uploads that didn't finish, files kept
  offline, backed-up photos, the index and Telegram's own records), with
  Clear or Free up only where nothing is lost; Settings › Space on this
  phone opens it there. Opened files are trimmed once a day, for as long
  as the drive stays open, to a budget of a tenth of the phone's storage
  or a third of what is free, whichever is less, between 100 MB and 1 GB,
  the ones opened longest ago going first. A split file joined back
  together to open it goes after two weeks. A phone with under 300 MB free
  is trimmed further each time the drive opens and each day after.
  Nothing is trimmed while a transfer runs.
- **Real folders.** Create, rename, move and delete folders; breadcrumbs;
  list and grid views; sort by name, date, size or type. Show in folder,
  in any file's menu or its Details, opens the folder the file lives in
  and points it out for a moment. Starred, Recent and each category say
  which folder each file is in, and Trash says where each item goes back
  to.
- **Replace, keep both or skip.** Uploading, sharing in or moving a file
  whose name a file in that folder already has, in any case, asks what to
  do instead of quietly making a second one. Replace uploads the new file
  and puts the old one in Trash for 30 days, marked as replaced, so the
  last version is one tap away; Keep both saves the new one as "name
  (2).ext"; Skip leaves it out. With several clashes in one batch, one
  answer can stand for all of them. The new file's Details say where the
  previous version is and offer Restore previous version, which brings it
  back beside the new one. Renaming a file to a name a sibling already has
  is refused.
- **Star a folder.** A folder can be starred like a file, from its menu or
  the selection bar. Starred folders sit in a Starred group at the top of
  Home, each saying how many files it holds, in it and below it, and how
  big they are, so a folder four levels down is one tap away. They come
  first in Starred and in search results, and the star travels with the
  folder to your other phones.
- **Act on many at once.** Long-press a file, folder or photo, or tap
  Select, and the actions move to a bar along the bottom, each with its
  name: Download, Send, Move and Trash for files, Album, Send, Download
  and Trash for photos, and the rest under More. The top says how many are
  selected and what they weigh. Files, Photos, albums, Starred, Recent and
  each category all select this way, and Back lets go of the selection
  first.
- **Recent, as you use it.** Home lists the files you last opened, shared
  or sent on this phone together with the ones you added, each saying which
  and when. Backed-up photos stay in Photos, so a batch of them never
  pushes the rest out. See all splits the list into Opened and Added.
- **Fast and offline-friendly.** A local index (SQLite) makes browsing and
  search instant; the channel stays the source of truth. Photos fetches
  thumbnails only for what stops on screen, not for what scrolls past, and
  on Wi-Fi it fetches the newest ones ahead, so browsing them later on
  mobile data costs nothing.
- **Light on small phones.** Thumbnails are decoded at the size they are
  shown, and the Photos timeline, albums and category lists leave out the
  tiny inline previews, which each tile reads for itself. While backup
  sends photos up, the timeline takes in the new ones at most every
  three-quarters of a second rather than once per photo. Phones with
  little memory start in Save memory: one upload and two downloads at a
  time, one photo backing up at a time, a smaller image cache, previews
  drawn without blur, and Search inside documents off until you turn it
  on. Settings › This phone › Save memory turns it on or off, and says
  when it was the phone's memory that turned it on.
- **Syncs itself.** New, edited or deleted messages flow in live. Anything you
  **forward into the channel from Telegram** (documents, videos, audio, voice
  messages, photos) shows up in the drive with no re-upload. Write a folder
  name as the forward's comment, like `Wedding` or `#Taxes/2026`, and the
  files go straight into that folder; a `#` makes the folder if it isn't
  there. The same works for the caption on a file dropped into the channel
  from another Telegram app. Forwards with no folder named wait together
  under Forwarded at the top of Files, each saying who it came from, with
  Move all and Keep here.
- **Save from any chat.** Pick Saved Messages or any chat, a channel you only
  read included, choose its documents, photos and videos, or audio, and pick
  a folder. Telegram copies them into the drive itself, so nothing is
  downloaded or uploaded, and they keep their original dates. What the
  drive already has, and what a chat doesn't let you save, is left out of
  the list. Copies go one at a time in Transfers and carry on after a
  restart. Photos sent in a chat as photos are Telegram's compressed copies;
  files sent as documents come across intact.
- **Rebuildable.** Names, folders, stars, albums and the trash live in each
  message's caption. Reinstall, sign in on another phone, or sign out and
  back in, and the whole drive comes back. Signing out takes the drive off
  this phone, files kept offline included, and drops any delete still
  waiting out its Undo, so nothing is deleted after you have left.
- **Trash.** Deleting moves things to the trash for 30 days; restore or
  delete for good from Trash, where a file a newer upload replaced reads
  Replaced. Moving more than 100 items there asks first.
  Photos and videos this phone still has can leave the phone too: tick
  "Also delete from this phone" and, once Undo has had its time without
  being tapped, Android asks to delete them (if you have left the app by
  then, it asks when you are back). Undo, or restoring them from Trash
  before then, leaves the phone's copies untouched, and the box remembers
  your last answer.
- **Undo for every change.** Moving, renaming, starring, adding to or
  removing from an album, restoring and moving to the trash all offer Undo
  for six seconds (with TalkBack on, until you dismiss it), and an Undo
  that can't go through says why. Delete for good, Empty trash and Delete
  album take the items away at once but wait ten seconds, with Undo, before
  anything leaves Telegram; sending the app to the background deletes them
  straight away.
- **Tidy in Telegram too.** Captions lead with the plain file name; the
  machine-readable part sits in a spoiler, so the channel still reads like a
  file list.
- **Transfers that survive.** A queue with live speed and ETA, cancel and
  retry, and a time when everything in progress should be done. A failed
  transfer says why in one sentence, and Home and Transfers retry it in
  place. On Android a foreground service keeps uploads going in the
  background, and interrupted split uploads resume at the last finished
  part, saying how many parts are already in your drive. The service's
  notification has Pause while transfers you started are running, and a
  quiet "Transfers paused" notification then offers Resume. When your
  uploads or saves finish while Telegrive is in the background, one quiet
  notification says so: what went where, with Open for a single file, or
  how many didn't finish and why, with Retry. Files Telegram copies from a
  chat count as saved from Telegram, never as uploaded. Telegrive asks once
  to post notifications; when they are off, Settings says so, with Turn on.
  When the connection drops, uploads and downloads say "Waiting for
  network" and carry on by themselves once it is back, and a request that
  times out is tried again, up to three times in a row, before anything is
  called failed.
- **Fits a full phone.** Before Telegrive writes a big copy, a split part or
  a download, it checks the phone has room for it. Without room the
  transfer waits, says how much it needs and how much is free, and starts
  by itself once there is room: Home says the phone is nearly full and
  offers Free up space. A copy cut short, by Android stopping the app, say,
  is never sent; the transfer says to share or pick the file again. Copies
  made for uploads go when the upload is cancelled or removed, and
  leftovers are cleared each time the drive opens.
- **Careful with mobile data.** Starting 50 MB or more on mobile data asks
  first: "Later, on Wi-Fi" holds the uploads or downloads and starts them
  on their own on Wi-Fi, and Use mobile data on Transfers, or Use data on
  Home, lets them go at any time. Transfers of 200 MB or more started on
  Wi-Fi wait if the phone moves to mobile data (a setting, on by default),
  and they resume from what they already have. A phone's hotspot counts as
  mobile data, for transfers, photo backup and reading documents for
  search.
- **A monthly data limit.** Set one in Settings › Mobile data, with the day
  your plan renews, and photo backup stays inside it. Usage is what
  Telegram itself sent and received this period, and Settings shows it next
  to what went over Wi-Fi. Each photo or video is checked before it starts,
  so a video too big for what is left waits while the smaller photos behind
  it still go. Backup then says the limit is reached and carries on over
  Wi-Fi or once the plan renews; Use data anyway lets it go past the limit
  until the phone is next on Wi-Fi.
- **Patient with Telegram.** When Telegram asks for a pause, transfers count
  down and carry on by themselves; when it asks an upload, the other
  uploads hold off too, a split one before its next part, rather than send
  their bytes only to be turned away. Moving, starring, trashing or adding
  many items to an album shows its progress above the bar, or at the foot
  of a screen opened over it, with Stop, and waits out Telegram the same
  way.
- **Through a proxy where Telegram is blocked.** When Telegram hasn't
  answered for 20 seconds while the phone is online, the sign-in screens,
  setup and Home say it isn't reachable on this network and offer Use a
  proxy. Paste a tg://proxy, tg://socks or t.me/proxy link, or type an
  MTProto or SOCKS5 proxy's details, and Telegrive connects through it;
  Telegram's encryption still applies. Tapping a tg://proxy or tg://socks
  link in another app opens Telegrive, which shows the proxy's address and
  connects only once you tap Connect. Settings › Connection › Proxy lists
  the saved proxies with how quickly each answers, switches between them,
  removes them, or goes back to a direct connection. TDLib keeps them in
  its encrypted database.
- **Watch and read without downloading.** Videos, music, call recordings
  and audiobooks stream as they play, with seeking, even across a split
  file's parts. On mobile data only a short stretch ahead of what plays is
  fetched, and nothing more comes down once the player closes. Video and
  audio files say how long they run in their rows and in Details, as
  '1:12:40 · 1.2 GB', so the ten-minute recap stands out from the
  lectures around it. The player has a speed button that cycles from
  0.75× to 2× with the pitch kept natural, and remembers the last speed
  for audio and for video separately, so a lecture opens at 1.5× while
  music stays at 1×. Pressing and holding the picture while something
  plays runs it at 2× until you let go. The skip buttons and a double tap
  on either half of the picture jump 10 seconds on a short file and 30
  seconds on anything ten minutes or longer. Videos and long recordings
  pick up where you stopped (on this phone), with a Start over button for
  the first few seconds, and Home lists up to three you are partway
  through with how much is left; a file watched to its end starts from
  the beginning next time, and Mark as finished drops one from the list.
  Audio opened from a folder plays on to the next file in that folder, in
  the order the list shows, with Previous and Next in the player. PDFs open
  page by page without downloading the whole file, split ones included,
  and text files open in the app too. Everything else opens in the right
  app on your phone.
- **Search inside documents.** The words in PDFs and text files are read on
  the phone, so search finds documents by what they say. A document fetched
  only to be read is deleted again once it has been, so reading keeps no
  copies, and reading waits while the phone has under 200 MB free. Words
  and a date narrow each other: "invoice march 2024" finds the invoices
  from that month, and "last week" alone finds everything from then. A
  search from inside a folder starts limited to it and the folders below
  it; a search from Photos finds photos and videos and shows them as the
  grid. Each file in the results list says which folder it is in, and
  Starred, Recent and each category have a search button too.
- **Send in Telegram.** Send files, a whole folder or an album to any chat
  straight from the drive, with no re-upload, so it uses almost no data. An
  optional line goes first, starting as the folder's or album's name; each
  subfolder arrives under a line naming it, and an album's photos come in
  the order they were taken. The chats you sent to last come first in the
  list.
- **Share to Telegrive** from any app on Android, into the folder you pick.
  A photo or video from the gallery goes up from where it is, with no copy
  on the phone; anything else is copied first, and a file the phone has no
  room to copy is named in the sheet with the space it needs.
  Recent folders show up in the share sheet, so a tap sends a file
  straight there, with Undo, and a name that folder already has gets a
  number. The Save to Telegrive sheet starts on the last folder you used
  and offers the others, and asks Replace, Keep both or Skip for a name
  the folder already has. While app lock is on, the share sheet shows no
  folder names.
- **Scan or snap into a folder.** New › Scan a document straightens and
  crops paper pages into a PDF on the phone; Take a photo puts the picture
  straight into the folder you are in, not your gallery. You name it once
  and it uploads there; a name the folder already has gets a number, so
  both files are kept. Scanning needs Google Play services.
- **Other folders upload by themselves.** On the Backup screen, pick any
  folder on the phone, such as Recordings or Download › Bank, and each new
  file in it goes up once to Files › Auto upload, or a drive folder you
  choose.
- **In other apps' file pickers.** Turn on Settings › This phone › Show the
  drive in other apps to attach drive files anywhere Android's picker
  opens, browsing the drive's folders or searching them by name. Files on
  the phone open at once; others download while Telegrive is open, and a
  video picked into a player can skip ahead while it comes down.
- **Download to this phone.** Files, folders or the whole drive, in the
  drive's folders under Download › Telegrive; photos and videos can go back
  into the gallery.
- **Available offline.** Keep files or folders on the phone to open without
  a connection. Keeping a folder first says how many files it holds, how
  big they are and how much room the phone has. New files in a kept folder
  follow on their own, those of 20 MB or more over Wi-Fi only; switch on
  Only over Wi-Fi and every kept file waits for Wi-Fi unless you tap
  Download now. Available offline, under Storage on Home and in Settings,
  lists what is kept and how far along each is, says which copies wait for
  room on the phone, retries what failed, and stops keeping a file or
  folder, or all of them.
- **App lock** with the phone's fingerprint, face or screen lock.
- **Private by default.** API credentials and the local-database key live in
  the platform keystore. TDLib's cache is encrypted from the first launch.
  Telegrive never shows you as "online" to your contacts.

## Getting started

1. The app's Telegram API credentials live in the git-ignored
   `lib/core/config/telegram_api.dart`. On a fresh clone, copy the template
   and fill in an `api_id` / `api_hash` from
   [my.telegram.org](https://my.telegram.org/apps) → API development tools:

   ```bash
   cp lib/core/config/telegram_api.example.dart lib/core/config/telegram_api.dart
   ```

2. Run it on an Android device or emulator:

   ```bash
   flutter pub get
   flutter run
   ```

3. Sign in with your phone number (or a QR code from another device). The
   first time, Telegrive creates a private channel called **Telegrive** with
   the app icon as its photo (archived in Telegram so it stays out of your
   chat list) and offers to back up your photos.

## Platform support

| Platform | Status |
| --- | --- |
| Android (arm64, armv7, x86, x86_64) | ✅ |
| iOS / macOS | Not yet. The UI is ready, but the TDLib binding (`handy_tdlib`) ships Android binaries only. See the roadmap. |

## Photo backup

- **Scope.** Every photo (and, optionally, video) on the phone, minus any
  device folders you switch off. Folders that appear later are included.
- **Where it goes.** `My Drive › Photo backup › <device folder>`, originals
  in full quality with their capture date and GPS data intact, plus a
  preview thumbnail so videos have posters too, and each video's length.
- **Out of the way.** Screenshots and chat folders back up too but stay out
  of the Photos view unless you show them; change this per folder in Backup
  settings.
- **Exactly once.** Each photo's device id is remembered, and anything
  already in the drive with the same name and size (after a reinstall, or
  from an old phone) is recognised and skipped.
- **Mobile data.** Don't use (the default), Photos only, or Photos and
  videos. With Photos only, videos wait for Wi-Fi, and one that is going up
  when the phone leaves Wi-Fi steps back and carries on from where it was
  once Wi-Fi returns. Files from other folders wait for Wi-Fi unless it is
  Photos and videos. With a monthly limit set, each one is checked against
  what is left of it before it starts.
- **Nothing silently skipped.** A photo that fails is tried again a few
  seconds later. After three tries it is listed under Backup › Not backed
  up with the reason, and can be retried or skipped one by one. The same
  screen lists the newest photos still waiting, with Back up now to send
  one ahead of the rest. Photos points to it while something is stuck,
  and Home's line about what didn't back up opens it.
- **Notices gaps.** After every full read of the channel, the photos backed
  up from this phone are matched against the index. Any whose file is gone
  from the drive are counted on the Backup screen and in Check my drive,
  and nothing is sent up again until you tap Back up again, or Leave them
  out to stop asking. A photo you deleted for good in Telegrive on this
  phone is remembered and never offered back. When so many look gone that
  the index itself is in doubt, it says the backup can't be checked yet
  instead.
- **Keeps going.** A pass runs when the drive opens, when the app comes back
  to the foreground, and whenever the photo library changes while the app is
  alive; a foreground service keeps it running in the background.
- **Other folders.** Pick any folder on the phone (Recordings, Download ›
  Bank); new files in it upload once to Files › Auto upload, or a folder
  you choose. Checked when Telegrive opens and while it runs. Each folder
  sends Documents and PDFs, Audio or Everything, with or without its
  subfolders, and when you add it you say whether the files already there
  go too. A file goes up once it has been left alone for a minute, so one
  still being written waits and is looked at again a little over a minute
  later, and one the drive already has under the same name and size is
  passed over. The uploads show in Transfers like any
  other. Android's folder picker grants read access to that folder alone,
  so no storage permission is asked for, and the list stays on this phone;
  signing out gives every folder's access back.
- **When the app is closed**, Android wakes a tiny job the moment new photos
  land (a MediaStore content trigger) and every few hours as a fallback. It
  posts "N new photos to back up"; tapping it, or Back up now, opens the
  app, which backs them up. Swiping it away puts it off for a day, after
  which it comes back if photos are still waiting.

## How it works

```text
Telegram (source of truth)                 This device
┌──────────────────────────────┐    sync    ┌─────────────────────────────┐
│ private channel "Telegrive"   │ ─────────▶ │ index (Drift/SQLite)        │
│  • file message              │  live +    │  folders · files · parts    │
│    caption: name + gr1:{…}   │  catch-up  │                             │
│  • folder message            │ ◀───────── │ transfer queue (persisted)  │
│    text: 📁 name + grf1:{…}  │  changes   │  uploads · downloads         │
└──────────────────────────────┘            └─────────────────────────────┘
```

- **Files** carry a manifest in their caption: id, name, folder, MIME type,
  size, dates, star, and `partIndex`/`partCount` for split files. A file
  that Replace sent to the trash also names the file that replaced it;
  restoring it clears that again. A video or audio file carries its length
  in seconds when it is known: read from the file as it goes up, from the
  gallery for a backed-up video, or from Telegram for a forwarded one. A
  length first learned by playing the file is kept on the phone and written
  into the caption the next time that caption is edited anyway, so knowing
  it never costs an edit of its own.
- **Folders** are small text messages carrying their own id, name, parent
  and star, so renames, moves and stars are a single edit and two devices
  never overwrite each other's folder tree.
- **Newer versions can add to a manifest.** Keys this install doesn't know
  are kept in the index and written back on its own edits, so a rename or
  move made here doesn't lose what a newer version stored.
- **Changes go to Telegram first.** The index is written from the message
  Telegram sends back, so it never claims something the channel doesn't have.
- **Sync** runs live while the app is open, catches up incrementally on launch
  and on pull-to-refresh, and does a full reconciliation daily, once on the
  first launch after an update that changes how messages are indexed, and
  from Settings → Rebuild index.
- **The index belongs to one account.** Signing out wipes it along with the
  sync checkpoints, so signing back in reads the channel again instead of
  showing an empty drive. A different account signing in wipes the previous
  one's index before its own drive opens. A session ended from Telegram
  closes the drive and keeps the index for seven days, so signing back in
  soon shows it at once; after that it is wiped too.
- **Forwards are filed by their comment.** A file that arrives without a
  manifest is a forward, or a file sent from another Telegram app, whose
  own caption is read instead. The plain text message sent just before a
  burst of forwards is its comment; if it names a folder, each file is
  moved there the way a move works for any forward (Telegram copies it into
  a message of the drive's own, with the manifest on it, and the forward
  goes), and the comment is deleted once every file it covered has moved.
  Only forwards newer than the first sync after the update are filed, so
  nothing that was already in the channel moves on its own.

## Project layout

```text
lib/
├── app/               # app root, router (phase-driven), shell, theme
├── core/              # config, formatting, file kinds, shared widgets
├── infrastructure/
│   ├── telegram/      # TDLib client, background receiver, secure storage
│   ├── database/      # Drift schema and queries (the local index)
│   └── storage/       # small preferences
└── features/
    ├── auth/          # welcome, credentials, phone/code/password/QR
    ├── setup/         # splash, find-or-create (and brand) the drive channel
    ├── drive/         # manifest format, indexer, repository, sync
    ├── transfers/     # upload/download queue, background keep-alive
    ├── backup/        # photo backup: controller, worker, notification, UI
    ├── files/ home/ photos/ search/ settings/ viewer/
```

Riverpod 3 for state, go_router for navigation (sign-in screens follow the
TDLib authorization state instead of being pushed by hand), and Drift for the
index. TDLib types stay inside `infrastructure/` and `features/*/data`.

## Development

```bash
flutter test                                              # unit + DB tests
dart run build_runner build                               # after schema changes
flutter test tool/screenshots/screens_test.dart --update-goldens  # UI renders with sample data
flutter test tool/icon/icon_test.dart --update-goldens && dart run flutter_launcher_icons
```

The screenshot harness renders the signed-in screens with fake data, so UI
work doesn't need a Telegram account.

A schema version bump also dumps the new schema into `drift_schemas/` and
regenerates the helpers `test/migration_test.dart` checks upgrades with; the
two commands are at the top of that test.

## Roadmap

- **Newer TDLib and 16 KB page support.** `handy_tdlib` bundles TDLib 1.8.36,
  and its binaries aren't 16 KB-page aligned. Android 15+ devices with 16 KB
  pages run the app in compatibility mode, and Play Store uploads need
  alignment. The plan is to vendor current `libtdjson` builds.
- **iOS and macOS**, using prebuilt TDLib xcframeworks through the same FFI
  binding.
- **End-to-end encryption** of file bodies and captions with a recovery
  passphrase.
- **Fully unattended background backup** with the app closed. Today the
  closed-app job notifies and the app does the upload; running TDLib inside
  the background job would remove that tap.
- **Share-sheet intake on iOS**, which needs a share extension.

## Good to know

- Keep the **Telegrive** channel. Deleting it deletes your drive. Deleting or
  editing its messages in Telegram changes the drive accordingly. An
  auto-delete timer set on the channel in Telegram deletes your files when
  it runs out; Check my drive warns about one and can turn it off.
- Telegram › Settings › Devices lists this phone by its model and Android
  version. Ending the session there signs Telegrive out here; Welcome says
  when that happened, and your files stay in the channel.
- Split files appear in Telegram as numbered parts (`movie.mkv.001`, …). Only
  Telegrive joins them back.
- A forward whose comment names a folder goes into it; `Wedding` finds the
  folder by its path from the root or by its name when only one folder has
  it, and `#Taxes/2026` makes what is missing. A comment that names no
  folder moves nothing, and the file waits under Forwarded at the top of
  Files until you move it or tap Keep here. Forwards that were already in
  the channel the first time this version read it stay where they are.
- A video the phone's player can't decode in the viewer, such as some MKV
  files, keeps its poster and offers Open with another app instead.
- Replace moves the old file to Trash only once the new upload has landed,
  so a cancelled or failed upload leaves the old file as it was. Photo
  backup never asks about name clashes; it recognises its own photos by
  name and size.
- A group in slow mode takes one message at a time, so sending there
  delivers the first file only, and says so.
- When Telegram asks for a pause longer than five minutes, Telegrive lets the
  phone sleep rather than keep it awake, so a transfer may wait until you next
  open the app.
- Files you open, stream or download yourself count toward the monthly
  data limit but are never held back by it, so heavy use on mobile data
  can leave backup waiting for Wi-Fi or the next period.
- While the app is closed, the job that notices new photos doesn't know
  about the monthly limit, so it may still say there are photos to back up
  when the limit holds them.
- Saving a file to the phone needs room for it twice over for a moment,
  since it is downloaded first and then copied into Download, the gallery
  or offline; the transfer says exactly how much it needs.
- Signing out forgets the saved proxies along with the rest of Telegram's
  data on the phone, so a blocked network needs the proxy again for the
  next sign-in. Where Telegram is set to open proxy links, tapping one
  goes there; paste it into Telegrive instead.
- Transfers that step back to wait for Wi-Fi keep Telegrive running in the
  background for ten minutes. If Wi-Fi takes longer, they start when it
  returns while the app is still running, or the next time you open it.
- A watched folder sends each file once. A file changed after it went up
  isn't sent again, and one renamed on the phone looks new and goes up
  again under its new name. Folders are only checked while Telegrive runs.
- Android's file picker shows the drive only while app lock is off, since
  the picker can't ask for a fingerprint; turning app lock off brings it
  back. Signing out, or a session ended from Telegram, takes it out of the
  picker until it is turned on again after the next sign-in. A file that
  isn't on the phone comes down only while Telegrive is running, on screen
  or in the background. On Android 7 it arrives from its start only, so an
  app that jumps around in a file may not read it until the file is on the
  phone.
- Where you stopped in a video or recording is kept on this phone only, for
  files of three minutes or longer and for 60 days after you last played
  them. Rebuild index keeps these points; signing out clears them.

Telegrive is an independent project, not affiliated with Telegram.
