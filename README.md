# Telegrive

Your Telegram account as an unlimited drive, with automatic photo backup.

Telegrive keeps your files in a private channel on your own Telegram
account and gives you a proper file manager on top of it. There is no
Telegrive server and no new account: you sign in with your Telegram phone
number, and your files stay in Telegram, where you can see them too.

<p>
<img src="tool/screenshots/out/home_light.png" width="23%" alt="Home">
<img src="tool/screenshots/out/files_list.png" width="23%" alt="Files">
<img src="tool/screenshots/out/photos.png" width="23%" alt="Photos">
<img src="tool/screenshots/out/backup_settings.png" width="23%" alt="Photo backup">
</p>

## What you get

- **Room for everything.** Keep as much as you like, and files of any
  size: big ones are cut into parts and joined back when you open them.
- **Photo backup.** Turn it on once and your camera roll goes up in full
  quality. New photos follow on their own, even with the app closed
  while the phone charges. Free up space on the phone afterwards, and
  keep the last 30 or 90 days if you like.
- **A real file manager.** Folders, stars, albums, a photo timeline, and
  a trash that keeps things for 30 days. Every change can be undone.
- **Search that finds things.** By name, by date ("invoices march 2024"),
  and by the words inside PDFs, text files and scanned pages.
- **Watch and read without downloading.** Videos and music stream as they
  play, at the speed you choose; PDFs open page by page.
- **Works offline.** Browsing is instant, and changes made without a
  connection go to Telegram once you are back online.
- **Easy on your data plan.** Big transfers can wait for Wi-Fi, photo
  backup can stay inside a monthly limit, and a small copy of a new photo
  can go first with the original following on Wi-Fi.
- **Part of your phone.** Share files in from any app, scan a document
  straight into a folder, send files to any Telegram chat without
  uploading them again, and attach drive files in other apps.
- **Private.** App lock with your fingerprint or face, an encrypted cache
  on the phone, and Telegrive never shows you as online to your contacts.

## Getting started

1. Telegrive runs on Android and iPhone. It isn't in a store yet; to
   build it, and for what the iPhone doesn't do yet, see
   [TECHNICAL.md](TECHNICAL.md).
2. Sign in with your phone number, or scan a QR code from Telegram on
   another device.
3. Telegrive makes a private channel called **Telegrive** in your account,
   archived so it stays out of your chat list, and offers to back up your
   photos.

On a new phone, or after reinstalling, sign in the same way and your whole
drive comes back.

## Your files in Telegram

Open the Telegrive channel in Telegram and it reads like a file list:

- Each file is a message, with its name in bold and its folder as a
  hashtag. Tap `#Invoices` to see everything in that folder, or
  `#starred` and `#trash` for your stars and your trash.
- Each folder is a short message of its own, saying which folder it is in.
- The message pinned at the top says what the channel is.
- At the bottom of each message, folded under a spoiler, are the details
  Telegrive reads. Leave those as they are.
- Files bigger than Telegram allows in one message show up as numbered
  parts (`movie.mkv.001`, `movie.mkv.002`, …). Telegrive joins them back.
- Forward a file into the channel and it shows up in your drive. Write a
  folder name, like `Wedding`, as the forward's comment and it goes
  straight into that folder.

## Good to know

- **Keep the channel.** Deleting it deletes your drive, and deleting a
  message in it deletes that file. If you turn on an auto-delete timer for
  the channel, Telegram deletes your files when it runs out; Settings ›
  Check my drive warns you and can turn it off.
- **Your files are as private as your Telegram account.** The channel is
  private and only you are in it, but like any Telegram cloud chat it
  isn't end-to-end encrypted. Turning on two-step verification in Telegram
  protects it better; Check my drive tells you if it is off.
- **Signing out** takes the drive off this phone. Your files stay in
  Telegram. Ending Telegrive's session in Telegram › Settings › Devices
  signs it out too.
- **Telegram's limits apply.** A file goes into one message up to 2 GB
  (4 GB with Premium); anything bigger becomes parts. When Telegram asks
  for a pause, transfers wait and carry on by themselves.

## For developers

How the drive is stored in Telegram, how the app is built, and how to run
it from source are in [TECHNICAL.md](TECHNICAL.md). The design rules are in
[DESIGN.md](DESIGN.md).

Telegrive is an independent project, not affiliated with Telegram.
