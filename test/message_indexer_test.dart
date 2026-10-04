import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/data/message_indexer.dart';
import 'package:telegrive/features/drive/domain/manifest.dart';

import 'support/fake_telegram.dart';

/// Server message 5, the way TDLib numbers it.
const _id = 5 << 20;

/// A voice message forwarded into the channel, with [caption].
td.Message _voice({String mimeType = 'audio/ogg', String caption = ''}) =>
    channelMessage(
      _id,
      td.MessageVoiceNote(
        voiceNote: td.VoiceNote(
          duration: 12,
          waveform: '',
          mimeType: mimeType,
          voice: tdFile(7, size: 48 * 1024),
        ),
        caption: td.FormattedText(text: caption, entities: const []),
        isListened: false,
      ),
      date: 1_757_664_000,
      editDate: 1_757_667_600,
    );

void main() {
  test('a forwarded voice message is adopted at the root as audio', () {
    final entry = MessageIndexer.entryFor(_voice()) as FilePartEntry;

    expect(entry.file.id.value, 'tg$_id');
    expect(entry.file.name.value, 'voice_5.ogg');
    expect(entry.file.mimeType.value, 'audio/ogg');
    expect(entry.file.kind.value, FileKind.audio);
    expect(entry.file.folderId.value, isNull);
    expect(entry.file.size.value, 48 * 1024);
    expect(
      entry.file.createdAt.value,
      DateTime.fromMillisecondsSinceEpoch(1_757_664_000 * 1000),
    );
    expect(
      entry.file.modifiedAt.value,
      DateTime.fromMillisecondsSinceEpoch(1_757_667_600 * 1000),
    );
    expect(entry.part.tdFileId.value, 7);
    expect(entry.part.messageId.value, _id);
  });

  test('a voice message recorded as MP3 is named .mp3', () {
    final entry = MessageIndexer.entryFor(
      _voice(mimeType: 'audio/mpeg'),
    ) as FilePartEntry;

    expect(entry.file.name.value, 'voice_5.mp3');
    expect(entry.file.kind.value, FileKind.audio);
  });

  test('a voice message recorded as MP4 or AAC is named .m4a', () {
    for (final mimeType in ['audio/mp4', 'audio/aac']) {
      final entry =
          MessageIndexer.entryFor(_voice(mimeType: mimeType)) as FilePartEntry;

      expect(entry.file.name.value, 'voice_5.m4a');
      expect(entry.file.mimeType.value, mimeType);
      expect(entry.file.kind.value, FileKind.audio);
    }
  });

  test('a voice message with no type is Ogg', () {
    final entry =
        MessageIndexer.entryFor(_voice(mimeType: '')) as FilePartEntry;

    expect(entry.file.name.value, 'voice_5.ogg');
    expect(entry.file.mimeType.value, 'audio/ogg');
  });

  test('a message without a manifest is indexed as adopted, one with it is not', () {
    final adopted = MessageIndexer.entryFor(_voice()) as FilePartEntry;
    expect(adopted.file.adopted.value, isTrue);
    expect(MessageIndexer.isAdopted(_voice()), isTrue);

    final at = DateTime(2025, 9, 12);
    final caption = ManifestCodec.encodeFile(
      FileManifest(
        id: 'k3v9',
        name: 'Selam, Friday.ogg',
        folderId: null,
        mimeType: 'audio/ogg',
        size: 48 * 1024,
        createdAt: at,
        modifiedAt: at,
      ),
    ).text;
    final own = MessageIndexer.entryFor(_voice(caption: caption)) as FilePartEntry;
    expect(own.file.adopted.value, isFalse);
    expect(MessageIndexer.isAdopted(_voice(caption: caption)), isFalse);
  });

  test('a post is read for the filer: media, comment, or the drive\'s own record', () {
    final media = MessageIndexer.postOf(
      documentMessage(
        21,
        'look',
        date: 1001,
        forwardedFrom: const td.MessageOriginHiddenUser(senderName: 'Selam'),
        albumId: 7,
      ),
    );
    expect(media.id, 21);
    expect(media.date, 1001);
    expect(media.media, isTrue);
    expect(media.manifest, isFalse);
    expect(media.forwarded, isTrue);
    expect(media.caption, 'look');
    expect(media.text, isNull);
    expect(media.albumId, 7);

    final comment = MessageIndexer.postOf(textMessage(20, 'Wedding', date: 1000));
    expect(comment.text, 'Wedding');
    expect(comment.media, isFalse);
    expect(comment.manifest, isFalse);
    expect(comment.forwarded, isFalse);

    final folder = MessageIndexer.postOf(
      textMessage(_id, '📁 Invoices\ntgrf1:{"id":"inv","n":"Invoices"}'),
    );
    expect(folder.text, isNull);
    expect(folder.manifest, isTrue);
  });

  test('a voice message with a manifest is read from it', () {
    final at = DateTime(2025, 9, 12);
    final caption = ManifestCodec.encodeFile(
      FileManifest(
        id: 'k3v9',
        name: 'Selam, Friday.ogg',
        folderId: 'calls',
        mimeType: 'audio/ogg',
        size: 48 * 1024,
        createdAt: at,
        modifiedAt: at,
      ),
    ).text;
    final entry =
        MessageIndexer.entryFor(_voice(caption: caption)) as FilePartEntry;

    expect(entry.file.id.value, 'k3v9');
    expect(entry.file.name.value, 'Selam, Friday.ogg');
    expect(entry.file.folderId.value, 'calls');
    expect(entry.file.kind.value, FileKind.audio);
  });

  test('a length and a replacement in the caption land in their columns', () {
    final at = DateTime(2025, 9, 12);
    FileManifest manifest({int? durationSeconds, String? replacedBy}) =>
        FileManifest(
          id: 'k3v9',
          name: 'clip.mp4',
          folderId: null,
          mimeType: 'video/mp4',
          size: 9,
          createdAt: at,
          modifiedAt: at,
          trashedAt: replacedBy == null ? null : at,
          durationSeconds: durationSeconds,
          replacedBy: replacedBy,
        );
    FilePartEntry entry(FileManifest m) => MessageIndexer.entryFor(
      documentMessage(_id, ManifestCodec.encodeFile(m).text),
    ) as FilePartEntry;

    final known = entry(manifest(durationSeconds: 90, replacedBy: 'new')).file;
    expect(known.durationSeconds.value, 90);
    expect(known.replacedBy.value, 'new');

    // No length in the caption leaves one learned on this phone alone,
    // while no replacement means there is none.
    final plain = entry(manifest()).file;
    expect(plain.durationSeconds.present, isFalse);
    expect(plain.replacedBy.present, isTrue);
    expect(plain.replacedBy.value, isNull);
  });

  test('a forwarded video or audio file takes its length from Telegram', () {
    td.Message video({int duration = 84, String caption = ''}) =>
        channelMessage(
          _id,
          td.MessageVideo(
            video: td.Video(
              duration: duration,
              width: 1920,
              height: 1080,
              fileName: 'clip.mp4',
              mimeType: 'video/mp4',
              hasStickers: false,
              supportsStreaming: true,
              video: tdFile(9, size: 84 * 1024 * 1024),
            ),
            caption: td.FormattedText(text: caption, entities: const []),
            showCaptionAboveMedia: false,
            hasSpoiler: false,
            isSecret: false,
          ),
        );
    final clip = (MessageIndexer.entryFor(video()) as FilePartEntry).file;
    expect(clip.kind.value, FileKind.video);
    expect(clip.durationSeconds.value, 84);

    // A length Telegram doesn't know leaves one learned here alone.
    final unknown =
        (MessageIndexer.entryFor(video(duration: 0)) as FilePartEntry).file;
    expect(unknown.durationSeconds.present, isFalse);

    // The app's own caption says how long the file is, whatever Telegram
    // makes of the container.
    final at = DateTime(2025, 9, 12);
    final own = ManifestCodec.encodeFile(
      FileManifest(
        id: 'k3v9',
        name: 'clip.mp4',
        folderId: null,
        mimeType: 'video/mp4',
        size: 9,
        createdAt: at,
        modifiedAt: at,
        durationSeconds: 90,
      ),
    ).text;
    final captioned =
        (MessageIndexer.entryFor(video(caption: own)) as FilePartEntry).file;
    expect(captioned.durationSeconds.value, 90);

    final track = channelMessage(
      _id,
      td.MessageAudio(
        audio: td.Audio(
          duration: 300,
          title: 'Tizita',
          performer: '',
          fileName: 'tizita.mp3',
          mimeType: 'audio/mpeg',
          externalAlbumCovers: const [],
          audio: tdFile(10),
        ),
        caption: td.FormattedText(text: '', entities: const []),
      ),
    );
    final audio = (MessageIndexer.entryFor(track) as FilePartEntry).file;
    expect(audio.kind.value, FileKind.audio);
    expect(audio.durationSeconds.value, 300);

    final voice = (MessageIndexer.entryFor(_voice()) as FilePartEntry).file;
    expect(voice.durationSeconds.value, 12);
  });

  test('a starred folder is indexed starred', () {
    FolderEntry entry(String json) =>
        MessageIndexer.entryFor(textMessage(_id, '📁 Invoices\ntgrf1:$json'))
            as FolderEntry;

    expect(
      entry('{"id":"inv","n":"Invoices","st":1}').folder.starred.value,
      isTrue,
    );
    expect(entry('{"id":"inv","n":"Invoices"}').folder.starred.value, isFalse);
  });

  test('the voice file is what gets downloaded and streamed', () {
    final message = _voice();
    final voice = (message.content as td.MessageVoiceNote).voiceNote.voice;

    expect(MessageIndexer.mediaFile(message), voice);
  });

  test('round video notes stay out of the drive', () {
    final message = channelMessage(
      _id,
      td.MessageVideoNote(
        videoNote: td.VideoNote(
          duration: 5,
          waveform: '',
          length: 240,
          video: tdFile(8),
        ),
        isViewed: false,
        isSecret: false,
      ),
    );

    expect(MessageIndexer.entryFor(message), isNull);
    expect(MessageIndexer.mediaFile(message), isNull);
  });
}
