// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'OMNIA';

  @override
  String get emptyStageHint => 'Drop a file or a folder here';

  @override
  String get emptyStageSubtitle =>
      'Video, audio, PDF and text — everything plays here.';

  @override
  String get openFile => 'Open a file';

  @override
  String get openFolder => 'Open a folder';

  @override
  String get dropToPlay => 'Drop to play';

  @override
  String get play => 'Play';

  @override
  String get pause => 'Pause';

  @override
  String get mute => 'Mute';

  @override
  String get unmute => 'Unmute';

  @override
  String get fullscreen => 'Fullscreen';

  @override
  String get exitFullscreen => 'Exit fullscreen';

  @override
  String get minimize => 'Minimize';

  @override
  String get maximize => 'Maximize';

  @override
  String get restore => 'Restore';

  @override
  String get closeWindow => 'Close';

  @override
  String get alwaysOnTop => 'Always on top';

  @override
  String get alwaysOnTopNormal => 'Normal player';

  @override
  String get alwaysOnTopMini => 'Mini player';


  @override
  String get loading => 'Opening…';

  @override
  String get audioOnly => 'Audio';

  @override
  String speedValue(String speed) {
    return '$speed×';
  }

  @override
  String get resetSpeed => 'Normal speed';

  @override
  String get showRemainingTime => 'Show remaining time';

  @override
  String get showTotalTime => 'Show total duration';

  @override
  String get errorTitle => 'This file cannot be played';

  @override
  String get errorFileNotFound =>
      'The file cannot be found. It may have been moved or deleted.';

  @override
  String get errorUnsupported => 'This file type is not supported by OMNIA.';

  @override
  String get errorDecode =>
      'The file looks damaged, or its format cannot be decoded by the engine.';

  @override
  String get errorPermission =>
      'OMNIA is not allowed to read this file or folder.';

  @override
  String get errorEmptyFolder => 'This folder holds no file OMNIA can read.';

  @override
  String get errorUnknown => 'An unexpected error occurred during playback.';

  @override
  String get errorHint => 'You can open another file, or drop one here.';

  @override
  String get openAnotherFile => 'Open another file';

  @override
  String get panelShow => 'Show panel';

  @override
  String get panelHide => 'Hide panel';

  @override
  String get panelSearchPlaceholder => 'Search this folder';

  @override
  String get panelScanning => 'Scanning folder…';

  @override
  String get panelEmpty => 'No readable file in this folder';

  @override
  String panelNoResults(String query) {
    return 'No result for “$query”';
  }

  @override
  String get panelNoFolder => 'Open a file to see its neighbours';

  @override
  String panelFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
      zero: 'no file',
    );
    return '$_temp0';
  }

  @override
  String panelFileCountFiltered(int visible, int total) {
    return '$visible of $total';
  }

  @override
  String get filterAll => 'All';

  @override
  String get filterVideo => 'Video';

  @override
  String get filterAudio => 'Audio';

  @override
  String get filterDocuments => 'Documents';

  @override
  String get filterImages => 'Images';


  @override
  String get sortLabel => 'Sort';

  @override
  String get sortName => 'Name';

  @override
  String get sortDate => 'Date';

  @override
  String get sortSize => 'Size';

  @override
  String get sortType => 'Type';

  @override
  String get sortAscending => 'Ascending';

  @override
  String get sortDescending => 'Descending';

  @override
  String get contextPlay => 'Play';

  @override
  String get contextRemove => 'Remove from list';

  @override
  String get contextReveal => 'Open file location';

  @override
  String get badgeWatched => 'Watched';

  @override
  String badgeResume(String time) {
    return 'Resume at $time';
  }

  @override
  String get nextFile => 'Next file';

  @override
  String get previousFile => 'Previous file';

  @override
  String get endModeLabel => 'When playback ends';

  @override
  String get endModeStop => 'Stop';

  @override
  String get endModeNext => 'Next file';

  @override
  String get endModeRepeatOne => 'Repeat file';

  @override
  String get endModeLoopFolder => 'Loop folder';

  @override
  String get endModeShuffle => 'Shuffle';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get resizePanel => 'Resize panel';

  @override
  String get osdMuted => 'Muted';

  @override
  String osdVolume(int volume) {
    return '$volume';
  }

  @override
  String get osdAlwaysOnTopOn => 'Always on top';

  @override
  String get osdAlwaysOnTopOff => 'Always on top off';

  @override
  String get menuSpeed => 'Speed';

  @override
  String get recentFiles => 'Recent files';

  @override
  String get clearRecent => 'Clear recent files';

  @override
  String get noRecentFiles => 'No recent file';

  @override
  String get recentMissing => 'File not found';

  @override
  String get helpTitle => 'Keyboard shortcuts';

  @override
  String get helpClose => 'Close help';

  @override
  String get helpSubtitle =>
      'Everything can be driven from the keyboard. Customise these shortcuts in Settings.';

  @override
  String get helpGroupPlayback => 'Playback';

  @override
  String get helpGroupNavigation => 'Navigation';

  @override
  String get helpGroupWindow => 'Window';

  @override
  String get helpPlayPause => 'Play / pause';

  @override
  String get helpSeekShort => 'Back / forward 5 s';

  @override
  String get helpSeekMedium => 'Back / forward 30 s';

  @override
  String get helpSeekLong => 'Back / forward 60 s';

  @override
  String get helpVolume => 'Volume up / down';

  @override
  String get helpSpeed => 'Speed up / down';

  @override
  String get helpPanelToggle => 'Show / hide the panel';

  @override
  String get helpLeaveSearch => 'Leave the search field';

  @override
  String get errorProtectedDocument =>
      'This document is password-protected. OMNIA cannot open it.';

  @override
  String get docPageLabel => 'Page';

  @override
  String docPageOf(int page, int total) {
    return '$page / $total';
  }

  @override
  String get docGoToPage => 'Go to page';

  @override
  String get docPreviousPage => 'Previous page';

  @override
  String get docNextPage => 'Next page';

  @override
  String get docZoomIn => 'Zoom in';

  @override
  String get docZoomOut => 'Zoom out';

  @override
  String docZoomValue(int percent) {
    return '$percent %';
  }

  @override
  String get docFitWidth => 'Fit width';

  @override
  String get docFitPage => 'Fit page';

  @override
  String get docRotate => 'Rotate 90°';

  @override
  String get docReadingDark => 'Reading dark mode';

  @override
  String get docLayoutContinuous => 'Continuous scrolling';

  @override
  String get docLayoutPaged => 'Page by page';

  @override
  String get docFind => 'Find';

  @override
  String get docFontSize => 'Text size';

  @override
  String docEncoding(String encoding) {
    return 'Encoding: $encoding';
  }

  @override
  String docLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lines',
      one: '1 line',
      zero: 'no line',
    );
    return '$_temp0';
  }

  @override
  String get findPlaceholder => 'Find in document';

  @override
  String findMatches(int index, int count) {
    return '$index / $count';
  }

  @override
  String get findNoMatch => 'No match';

  @override
  String get findNext => 'Next match';

  @override
  String get findPrevious => 'Previous match';

  @override
  String get findClose => 'Close find';

  @override
  String get panelTabFolder => 'Folder';

  @override
  String get panelTabOutline => 'Outline';

  @override
  String get panelTabPages => 'Pages';

  @override
  String get docNoOutline => 'This document has no outline';

  @override
  String get docLoading => 'Loading document…';

  @override
  String get helpGroupDocuments => 'Documents';

  @override
  String get subtitles => 'Subtitles';

  @override
  String get subtitlesOff => 'Subtitles off';

  @override
  String get subtitlesNone => 'None';

  @override
  String get subtitlesLoadFile => 'Load subtitle file…';

  @override
  String get subtitleDelay => 'Delay';

  @override
  String subtitleDelayValue(String seconds) {
    return '$seconds s';
  }

  @override
  String get subtitleSize => 'Subtitle size';

  @override
  String get audioTracks => 'Audio track';

  @override
  String get audioTrackAuto => 'Automatic';

  @override
  String get noTracks => 'No track';

  @override
  String get abLoop => 'A-B loop';

  @override
  String get abLoopSetA => 'Point A set';

  @override
  String get abLoopSetB => 'A-B loop on';

  @override
  String get abLoopCleared => 'A-B loop off';

  @override
  String get screenshot => 'Screenshot';

  @override
  String get screenshotSaved => 'Screenshot saved';

  @override
  String get image => 'Picture';

  @override
  String get aspectRatio => 'Aspect ratio';

  @override
  String get aspectAuto => 'Automatic';

  @override
  String get aspectWide => '16:9';

  @override
  String get aspectStandard => '4:3';

  @override
  String get aspectFill => 'Fill';

  @override
  String get videoZoom => 'Video zoom';

  @override
  String videoZoomValue(int percent) {
    return 'Zoom $percent %';
  }

  @override
  String get videoZoomReset => 'Normal zoom';

  @override
  String get videoRotate => 'Rotate video';

  @override
  String videoRotation(int degrees) {
    return 'Rotation $degrees°';
  }

  @override
  String get imageAdjust => 'Picture adjustments…';

  @override
  String get brightness => 'Brightness';

  @override
  String get contrast => 'Contrast';

  @override
  String get saturation => 'Saturation';

  @override
  String get resetAdjust => 'Reset';

  @override
  String get equalizer => 'Equalizer';

  @override
  String get equalizerOn => 'Equalizer on';

  @override
  String get equalizerOff => 'Equalizer off';

  @override
  String get equalizerPreset => 'Preset';

  @override
  String get presetNormal => 'Flat';

  @override
  String get presetRock => 'Rock';

  @override
  String get presetPop => 'Pop';

  @override
  String get presetJazz => 'Jazz';

  @override
  String get presetClassical => 'Classical';

  @override
  String get presetBass => 'Bass';

  @override
  String get presetTreble => 'Treble';

  @override
  String get presetVocal => 'Vocal';

  @override
  String get presetElectronic => 'Electronic';

  @override
  String get presetAcoustic => 'Acoustic';

  @override
  String get presetCustom => 'Custom';

  @override
  String get miniPlayer => 'Mini player';

  @override
  String get miniPlayerExit => 'Leave mini player';

  @override
  String get unknownArtist => 'Unknown artist';

  @override
  String get closePanel => 'Close';

  @override
  String get screenshotFailed => 'Screenshot failed';

  @override
  String get screenshotFailedHint =>
      'The screenshot folder cannot be written to. Pick another one in Settings.';

  @override
  String get keyCtrl => 'Ctrl';

  @override
  String get keyShift => 'Shift';

  @override
  String get keyAlt => 'Alt';

  @override
  String get keySpace => 'Space';

  @override
  String get keyEscape => 'Esc';

  @override
  String get keyTab => 'Tab';

  @override
  String get keyEnter => 'Enter';

  @override
  String get keyBackspace => 'Backspace';

  @override
  String get keyDelete => 'Del';

  @override
  String get keyInsert => 'Ins';

  @override
  String get keyHome => 'Home';

  @override
  String get keyEnd => 'End';

  @override
  String get keyPageUp => 'PgUp';

  @override
  String get keyPageDown => 'PgDn';

  @override
  String get keyMediaPlayPause => 'Play/Pause';

  @override
  String keyNumpad(String key) {
    return 'Num $key';
  }

  @override
  String get keyCtrlWheel => 'Ctrl+wheel';

  @override
  String get keyDoubleClick => 'double-click';

  @override
  String scSeekBackward(int seconds) {
    return 'Back $seconds s';
  }

  @override
  String scSeekForward(int seconds) {
    return 'Forward $seconds s';
  }

  @override
  String get scVolumeUp => 'Volume up';

  @override
  String get scVolumeDown => 'Volume down';

  @override
  String get scToggleMute => 'Mute / unmute';

  @override
  String get scSpeedUp => 'Speed up';

  @override
  String get scSpeedDown => 'Slow down';

  @override
  String get scToggleSubtitles => 'Show / hide subtitles';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsClose => 'Close settings';

  @override
  String get settingsSectionGeneral => 'General';

  @override
  String get settingsSectionPlayback => 'Playback';

  @override
  String get settingsSectionSubtitles => 'Subtitles';

  @override
  String get settingsSectionAudio => 'Audio';

  @override
  String get settingsSectionDocuments => 'Documents';

  @override
  String get settingsSectionShortcuts => 'Shortcuts';

  @override
  String get settingsSectionScreenshots => 'Screenshots';

  @override
  String get settingsSectionHistory => 'History';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get languageFrench => 'Français';

  @override
  String get languageEnglish => 'English';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get themeSystem => 'System';

  @override
  String get settingsEndModeHint =>
      'What OMNIA does when a file ends. Press L to change it while playing.';

  @override
  String get settingsResume => 'Resume playback';

  @override
  String get settingsResumeHint =>
      'When you reopen a file you stopped part-way through.';

  @override
  String get resumeAuto => 'Automatic';

  @override
  String get resumeAsk => 'Ask';

  @override
  String get resumeNever => 'Never';

  @override
  String get settingsSingleInstance => 'Single window';

  @override
  String get settingsSingleInstanceHint =>
      'Opening a file from the system reuses the open window. Applies at next launch.';

  @override
  String get settingsInAppOpenTarget => 'In-app opening';

  @override
  String get settingsInAppOpenTargetHint =>
      'Open files, folders and recents in current window or a new window.';

  @override
  String get inAppOpenCurrent => 'Current window';

  @override
  String get inAppOpenNew => 'New window';

  @override
  String get settingsRememberPlaybackState => 'Remember playback state';

  @override
  String get settingsRememberPlaybackStateHint =>
      'Save last read document page and media position to resume automatically.';

  @override
  String get settingsHistoryRetention => 'History retention';

  @override
  String get settingsHistoryRetentionHint =>
      'Duration before resetting reading progress on older files.';

  @override
  String get historyRetention7Days => '7 days';

  @override
  String get historyRetention30Days => '30 days';

  @override
  String get historyRetention90Days => '90 days';

  @override
  String get historyRetentionUnlimited => 'Always';

  @override
  String get openInNewWindow => 'Open in new window';

  @override
  String get openInCurrentWindow => 'Open in current window';

  @override
  String get settingsSeekStep => 'Seek step';

  @override
  String get settingsSeekStepHint =>
      '← and → keys. With Shift: 30 s; with Ctrl: 60 s.';

  @override
  String settingsSeconds(int seconds) {
    return '$seconds s';
  }

  @override
  String get settingsDefaultSpeed => 'Speed at launch';

  @override
  String get settingsStartupVolume => 'Volume at launch';

  @override
  String get startupVolumeLast => 'Last used';

  @override
  String get startupVolumeFixed => 'Fixed';

  @override
  String get settingsFixedVolume => 'Fixed volume';

  @override
  String get settingsSubtitleAutoLoad => 'Load automatically';

  @override
  String get settingsSubtitleAutoLoadHint =>
      'Subtitle files with the same name as the video are loaded when it opens.';

  @override
  String get settingsSubtitleDelay => 'Default delay';

  @override
  String get settingsSubtitleDelayHint =>
      'Applied to every video you open. Fine-tune it in 0.5 s steps.';

  @override
  String get settingsEqualizerHint =>
      'Fine-tune the bands during playback, in the Equalizer panel.';

  @override
  String get settingsPdfLayout => 'PDF scrolling';

  @override
  String get settingsReadingDarkHint =>
      'Gently inverts document colours, for reading in the dark.';

  @override
  String get settingsTextSizeHint =>
      'Size of text and Markdown files. Ctrl+wheel while reading.';

  @override
  String get settingsScreenshotFolder => 'Screenshot folder';

  @override
  String get settingsScreenshotFolderVideo => 'Video screenshot folder';

  @override
  String get settingsRecordingFolder => 'Audio recordings folder';

  @override
  String get settingsScreenshotFolderDefault => 'Default folder';


  @override
  String get settingsChooseFolder => 'Choose…';

  @override
  String get settingsResetFolder => 'Default';

  @override
  String get settingsScreenshotPattern => 'File names';

  @override
  String get tokenName => 'media name';

  @override
  String get tokenDate => 'date';

  @override
  String get tokenTime => 'capture time';

  @override
  String get tokenPosition => 'position in the media';

  @override
  String settingsScreenshotPreview(String example) {
    return 'Example: $example';
  }

  @override
  String get settingsRecentHint => 'Recently opened files, with their folder.';

  @override
  String get settingsClearPositions => 'Clear positions';

  @override
  String get settingsClearPositionsHint =>
      'OMNIA forgets where you stopped in each file. The recent list is kept.';

  @override
  String get settingsClearAll => 'Clear everything';

  @override
  String get settingsClearAllHint => 'Recent files and positions.';

  @override
  String get settingsDone => 'Cleared';

  @override
  String get shortcutsHint =>
      'Click a shortcut to change it, then press the new key combination.';

  @override
  String get shortcutsPress => 'Press the key combination…';

  @override
  String shortcutsConflict(String action) {
    return 'Already used by “$action”.';
  }

  @override
  String get shortcutsReplace => 'Replace';

  @override
  String get shortcutsCancel => 'Cancel';

  @override
  String get shortcutsReset => 'Restore';

  @override
  String get shortcutsResetAll => 'Restore all';

  @override
  String get shortcutsNone => 'None';

  @override
  String get shortcutsChange => 'Change shortcut';

  @override
  String resumePromptPosition(String time) {
    return 'Resume at $time?';
  }

  @override
  String resumePromptPage(int page) {
    return 'Resume at page $page?';
  }

  @override
  String get resumePromptScroll => 'Resume where you left off?';

  @override
  String get resumeAccept => 'Resume';

  @override
  String get resumeDecline => 'From the start';

  @override
  String get keyWheel => 'Wheel';

  @override
  String get startupFailureTitle => 'OMNIA could not prepare its data';

  @override
  String get startupFailureBody =>
      'The application data folder cannot be accessed. Check the free disk space and the permissions on your home folder, then start OMNIA again.';

  @override
  String get recordClip => 'Record a clip';

  @override
  String get stopRecording => 'Stop recording';

  @override
  String get recordingStarted => 'Recording';

  @override
  String get recordingSaved => 'Clip saved';

  @override
  String get recordingFailed => 'No clip recorded';

  @override
  String get recordingFailedHint =>
      'Playback did not move, or the capture folder cannot be written to.';

  @override
  String get moreControls => 'More controls';

  @override
  String get controlBarResize =>
      'Drag to adjust the width. Double-click: automatic width.';

  @override
  String get volumeLabel => 'Volume';
}
