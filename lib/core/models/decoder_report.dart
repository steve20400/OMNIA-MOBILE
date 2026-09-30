/// Ce que le moteur dit du média en cours de lecture.
///
/// Sans téléphone sous la main, c'est la seule façon de savoir pourquoi une
/// vidéo saccade : décodage matériel ou logiciel, images réellement affichées
/// contre images attendues, images perdues. Un fichier qui annonce 25 images
/// par seconde et n'en affiche que 8 se lit « au ralenti » ; le rapport le dit
/// en une ligne au lieu de le laisser deviner.
class DecoderReport {
  const DecoderReport({
    this.hwdec = '',
    this.decoder = '',
    this.container = '',
    this.width = 0,
    this.height = 0,
    this.fps = 0,
    this.actualFps = 0,
    this.droppedFrames = 0,
    this.decoderDroppedFrames = 0,
    this.cacheSeconds = 0,
  });

  /// Décodeur matériel réellement en service (`mediacodec-copy`), ou `no` /
  /// vide quand le processeur décode seul.
  final String hwdec;

  /// Codec du flux vidéo, tel que mpv le nomme (`mpeg4`, `h264`…).
  final String decoder;

  /// Conteneur du fichier (`avi`, `matroska,webm`, `mov,mp4,m4a…`).
  final String container;

  final int width;
  final int height;

  /// Cadence annoncée par le conteneur.
  final double fps;

  /// Cadence réellement rendue. Très en dessous de [fps] : le décodage ne suit
  /// pas, c'est le « ralenti » que l'utilisateur voit.
  final double actualFps;

  /// Images que la sortie vidéo a laissé tomber faute de temps.
  final int droppedFrames;

  /// Images que le décodeur lui-même a sautées.
  final int decoderDroppedFrames;

  /// Secondes de média lues d'avance par le démultiplexeur. Proche de zéro sur
  /// un fichier volumineux : c'est le stockage qui freine, pas le décodage.
  final double cacheSeconds;

  /// Vrai quand un décodeur matériel est réellement en service. mpv rend `no`
  /// quand il a renoncé au matériel, et une chaîne vide quand rien ne joue.
  bool get hardware => hwdec.isNotEmpty && hwdec != 'no';

  /// Total des images perdues, décodeur et sortie vidéo confondus.
  int get totalDroppedFrames => droppedFrames + decoderDroppedFrames;

  /// Ligne unique affichée sur le lecteur.
  String get summary {
    final parts = <String>[
      hardware ? 'Matériel ($hwdec)' : 'Logiciel',
      if (decoder.isNotEmpty) decoder,
      if (width > 0 && height > 0) '$width×$height',
      if (fps > 0) _fpsLabel,
      if (container.isNotEmpty) container,
      _droppedLabel,
      if (cacheSeconds > 0) 'cache ${cacheSeconds.round()} s',
    ];
    return parts.join(' · ');
  }

  String get _fpsLabel {
    final nominal = '${_round(fps)} i/s';
    // L'écart ne se signale que s'il se voit : un dixième d'image d'écart est
    // le bruit normal de la mesure.
    if (actualFps <= 0 || (fps - actualFps).abs() < 0.5) return nominal;
    return '$nominal (réel ${_round(actualFps)})';
  }

  String get _droppedLabel {
    final total = totalDroppedFrames;
    if (total == 0) return 'aucune image perdue';
    return total == 1 ? '1 image perdue' : '$total images perdues';
  }

  static String _round(double value) =>
      value >= 10 ? value.round().toString() : value.toStringAsFixed(1);

  /// Construit le rapport à partir des propriétés mpv brutes.
  ///
  /// Toute valeur absente, vide ou illisible vaut zéro : une propriété que
  /// cette version de mpv ne connaît pas ne doit pas faire disparaître la ligne.
  factory DecoderReport.fromMpv(Map<String, String> properties) {
    String text(String name) => properties[name]?.trim() ?? '';
    double number(String name) => double.tryParse(text(name)) ?? 0;
    int count(String name) => double.tryParse(text(name))?.round() ?? 0;

    return DecoderReport(
      hwdec: text('hwdec-current'),
      decoder: text('video-format'),
      container: text('file-format'),
      width: count('width'),
      height: count('height'),
      fps: number('container-fps'),
      actualFps: number('estimated-vf-fps'),
      droppedFrames: count('frame-drop-count'),
      decoderDroppedFrames: count('decoder-frame-drop-count'),
      cacheSeconds: number('demuxer-cache-duration'),
    );
  }

  @override
  String toString() => 'DecoderReport($summary)';
}
