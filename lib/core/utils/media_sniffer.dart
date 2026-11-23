import '../models/media_type.dart';

/// Les suffixes qu'ajoutent navigateurs et outils de téléchargement tant que
/// le fichier n'est pas complet : « film.mp4.part » (Firefox, yt-dlp),
/// « film.mp4.crdownload » (Chrome, Edge), « .download » (Safari),
/// « .opdownload » (Opera), « .!ut » et « .!qb » (BitTorrent), et les
/// morceaux de yt-dlp, « film.mp4.part-Frag12 ».
final RegExp _partialSuffix = RegExp(
  r'\.(part|crdownload|download|partial|opdownload|!ut|!qb|tmp|temp)$|\.part-frag\d+$',
  caseSensitive: false,
);

/// Les extensions des téléchargements inachevés, pour qu'un sélecteur de
/// fichiers les propose.
const partialDownloadExtensions = ['part', 'crdownload', 'download', 'partial', 'opdownload'];

/// Vrai si [name] porte la marque d'un téléchargement inachevé.
bool isPartialDownload(String name) => _partialSuffix.hasMatch(name);

/// [name] sans sa marque de téléchargement inachevé : « film.mp4.part »
/// redevient « film.mp4 », et c'est l'extension d'origine qui dit le type.
///
/// Comme VLC, OMNIA lit ce qui est déjà arrivé ; le moteur suit même un
/// fichier qui grossit encore.
String withoutPartialSuffix(String name) => name.replaceFirst(_partialSuffix, '');

/// Le type d'un fichier d'après ses premiers octets (au moins 12 ; 192 pour
/// reconnaître un flux MPEG-TS), `null` s'ils ne disent rien de connu.
///
/// Sert quand le nom ne dit rien : un téléchargement de Chrome s'appelle
/// « Non confirmé 123456.crdownload » tant qu'il n'est pas fini.
MediaType? sniffMediaType(List<int> head) {
  bool at(int offset, List<int> bytes) {
    if (head.length < offset + bytes.length) return false;
    for (var i = 0; i < bytes.length; i++) {
      if (head[offset + i] != bytes[i]) return false;
    }
    return true;
  }

  List<int> ascii(String text) => text.codeUnits;

  // Vidéo.
  if (at(0, const [0x1A, 0x45, 0xDF, 0xA3])) return MediaType.video; // Matroska, WebM
  if (at(4, ascii('ftyp'))) {
    // MP4 et parents : la marque dit si c'est un son seul.
    for (final brand in const ['M4A ', 'M4B ', 'M4P ', 'F4A ', 'F4B ']) {
      if (at(8, ascii(brand))) return MediaType.audio;
    }
    if (at(8, ascii('avif')) || at(8, ascii('heic')) || at(8, ascii('heix')) || at(8, ascii('mif1'))) {
      return MediaType.image;
    }
    return MediaType.video;
  }
  if (at(0, ascii('RIFF'))) {
    if (at(8, ascii('AVI '))) return MediaType.video;
    if (at(8, ascii('WAVE'))) return MediaType.audio;
    if (at(8, ascii('WEBP'))) return MediaType.image;
  }
  if (at(0, ascii('FLV'))) return MediaType.video;
  if (at(0, const [0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11])) return MediaType.video; // ASF, WMV
  if (at(0, const [0x00, 0x00, 0x01, 0xBA]) || at(0, const [0x00, 0x00, 0x01, 0xB3])) {
    return MediaType.video; // MPEG-PS, MPEG-1
  }
  if (head.length > 188 && head[0] == 0x47 && head[188] == 0x47) return MediaType.video; // MPEG-TS

  // Son.
  if (at(0, ascii('ID3'))) return MediaType.audio;
  if (at(0, ascii('fLaC'))) return MediaType.audio;
  if (at(0, ascii('OggS'))) return MediaType.audio;
  if (at(0, ascii('#!AMR'))) return MediaType.audio;
  if (at(0, ascii('MAC '))) return MediaType.audio; // Monkey's Audio
  if (at(0, ascii('wvpk'))) return MediaType.audio; // WavPack
  if (at(0, ascii('FORM')) && (at(8, ascii('AIFF')) || at(8, ascii('AIFC')))) return MediaType.audio;
  if (head.length >= 2 && head[0] == 0xFF && (head[1] & 0xE0) == 0xE0) return MediaType.audio; // MP3, AAC

  // Images et documents.
  if (at(0, const [0xFF, 0xD8, 0xFF])) return MediaType.image; // JPEG
  if (at(0, const [0x89, 0x50, 0x4E, 0x47])) return MediaType.image; // PNG
  if (at(0, ascii('GIF8'))) return MediaType.image;
  if (at(0, ascii('BM'))) return MediaType.image;
  if (at(0, ascii('%PDF'))) return MediaType.pdf;

  return null;
}
