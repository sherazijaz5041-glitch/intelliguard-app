// ============================================================
// tflite_detection_service.dart - Fully on-device AI inference.
// Mirrors detection.py's models, preprocessing, rolling-average
// confirmation buffers, and per-camera cooldown — but runs entirely
// on the phone via tflite_flutter, with zero network calls.
// ============================================================
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'local_db_service.dart';

class DetectionResult {
  final List<Map<String, String>> confirmedAlerts; // [{event_type, source}]
  DetectionResult(this.confirmedAlerts);
}

class TFLiteDetectionService {
  static final TFLiteDetectionService instance = TFLiteDetectionService._();
  TFLiteDetectionService._();

  // Feature flag for person detection using the custom MobileNetV2
  // binary classifier (person_model.tflite). Set to true to enable
  // restricted-zone alerts when a person is detected in the frame.
  // ── Runtime-togglable detection flags ──────────────────────────────────────
  // Settings screen can flip these live; no restart needed.
  static bool _fireDetectionEnabled = true;
  static bool _violenceDetectionEnabled = false; // intentionally off by default
  static bool _personDetectionEnabled = true;
  static bool _smokeDetectionEnabledFlag = true;

  static bool get fireDetectionEnabled => _fireDetectionEnabled;
  static bool get smokeDetectionEnabled => _smokeDetectionEnabledFlag;
  static bool get violenceDetectionEnabled => _violenceDetectionEnabled;
  static bool get personDetectionEnabled => _personDetectionEnabled;

  static void setFireDetection({required bool enabled}) => _fireDetectionEnabled = enabled;
  static void setSmokeDetection({required bool enabled}) => _smokeDetectionEnabledFlag = enabled;
  static void setViolenceDetection({required bool enabled}) => _violenceDetectionEnabled = enabled;
  static void setPersonDetection({required bool enabled}) => _personDetectionEnabled = enabled;

  // ── Runtime-adjustable thresholds ───────────────────────────────────────────
  static double _fireThresholdOverride = _fireAvgThreshold;
  static double _smokeThresholdOverride = _smokeAvgThreshold;

  static double get fireThreshold => _fireThresholdOverride;
  static double get smokeThreshold => _smokeThresholdOverride;

  static void setFireThreshold(double v) => _fireThresholdOverride = v.clamp(0.5, 0.99);
  static void setSmokeThreshold(double v) => _smokeThresholdOverride = v.clamp(0.5, 0.99);

  static const _cooldownSeconds = 60;
  static const _personConfidenceThreshold = 0.75; // raised from 0.50

  // A near-black frame (camera pointed at nothing, lens covered, room dark)
  // isn't something any of these classifiers were meaningfully trained to
  // read — but a softmax always outputs a confident-looking top class even
  // on pure noise/garbage input. Skip fire/smoke/violence classification
  // entirely below this brightness rather than trust a meaningless guess.
  static const _minBrightnessForClassification = 18.0;

  // Rolling-average buffer sizes and thresholds
  static const _fireBufferSize = 8;
  static const _fireAvgThreshold = 0.85;
  static const _fireMinFrames = 6;
  static const _fireMinFlamePixels = 16;
  static const _smokeBufferSize = 10;
  static const _smokeAvgThreshold = 0.82;
  static const _smokeMinFrames = 10;
  static const _vioBufferSize = 5;
  static const _vioConfirmThreshold = 4;
  static const _vioMinConfidence = 0.85;
  static const _rzBufferSize = 5;
  static const _rzConfirmThreshold = 4;

  // Instance fields
  Interpreter? _fireInterpreter;
  Interpreter? _violenceInterpreter;
  Interpreter? _personInterpreter;
  Map<String, String> _fireLabels = {};
  Map<String, String> _violenceLabels = {};
  Map<String, String> _personLabels = {};
  bool _ready = false;
  bool _analyzingFrame = false;
  LocalDbScope? _bufferScope;
  Future<void>? _initializationFuture;
  bool get isReady => _ready;

  static const _targetSize = 224;

  // Rolling-average and confirmation buffer maps (per cameraId)
  final Map<String, List<double>> _fireRollingProbs = {};
  final Map<String, List<double>> _smokeRollingProbs = {};
  final Map<String, List<String>> _violenceBuffers = {};
  final Map<String, List<String>> _restrictedBuffers = {};
  final Map<String, DateTime> _lastEventTime = {}; // key: "$cameraId|$eventType"

  Future<void> init() {
    if (_ready) return Future<void>.value();
    return _initializationFuture ??= _initializeModels().whenComplete(() {
      _initializationFuture = null;
    });
  }

  Future<void> _initializeModels() async {
    try {
      final options = InterpreterOptions()..threads = 2;
      _fireInterpreter = await Interpreter.fromAsset('assets/models/fire_smoke_model.tflite', options: options);
      if (_violenceDetectionEnabled) {
        _violenceInterpreter = await Interpreter.fromAsset('assets/models/violence_model.tflite', options: options);
      }
      if (_personDetectionEnabled) {
        _personInterpreter = await Interpreter.fromAsset('assets/models/person_model.tflite', options: options);
      }

      // ---- DIAGNOSTIC LOGGING (temporary) ----
      // Confirms actual on-device tensor dtypes/shapes. Expected: float32.
      // If it ever shows uint8/int8 instead, the .tflite export is quantized
      // while this code feeds it float [0,1] values — that mismatch alone
      // would explain garbage predictions.
      debugPrint('[DEBUG] Fire input:  ${_fireInterpreter!.getInputTensor(0).type} '
          '${_fireInterpreter!.getInputTensor(0).shape}');
      debugPrint('[DEBUG] Fire output: ${_fireInterpreter!.getOutputTensor(0).type} '
          '${_fireInterpreter!.getOutputTensor(0).shape}');
      if (_violenceDetectionEnabled && _violenceInterpreter != null) {
        debugPrint('[DEBUG] Violence input:  ${_violenceInterpreter!.getInputTensor(0).type} '
            '${_violenceInterpreter!.getInputTensor(0).shape}');
        debugPrint('[DEBUG] Violence output: ${_violenceInterpreter!.getOutputTensor(0).type} '
            '${_violenceInterpreter!.getOutputTensor(0).shape}');
      } else {
        debugPrint('[DEBUG] Violence: disabled — not loaded.');
      }
      if (_personDetectionEnabled && _personInterpreter != null) {
        debugPrint('[DEBUG] Person input:  ${_personInterpreter!.getInputTensor(0).type} '
            '${_personInterpreter!.getInputTensor(0).shape}');
        debugPrint('[DEBUG] Person output: ${_personInterpreter!.getOutputTensor(0).type} '
            '${_personInterpreter!.getOutputTensor(0).shape}');
      } else {
        debugPrint('[DEBUG] Person: disabled — not loaded.');
      }

      final fireLabelsRaw = jsonDecode(await rootBundle.loadString('assets/models/class_labels.json')) as Map<String, dynamic>;
      _fireLabels = {for (final e in fireLabelsRaw.entries) e.value.toString(): e.key}; // index -> name

      if (_violenceDetectionEnabled) {
        final vioLabelsRaw =
            jsonDecode(await rootBundle.loadString('assets/models/violence_class_labels.json')) as Map<String, dynamic>;
        _violenceLabels = {for (final e in vioLabelsRaw.entries) e.value.toString(): e.key};
      }

      if (_personDetectionEnabled) {
        final raw = await rootBundle.loadString('assets/models/person_labels.txt');
        final lines = raw.trim().split('\n');
        _personLabels = {for (var i = 0; i < lines.length; i++) i.toString(): lines[i].trim()};
        debugPrint('[DEBUG] Person labels: $_personLabels');
      }

      _ready = true;
    } catch (_) {
      // A later retry must not retain partially loaded native interpreters.
      dispose();
      rethrow;
    }
  }

  // ---------------------------------------------------------------------
  // Quick average-brightness check (0-255 scale), sampled on a coarse grid
  // for speed rather than every pixel. Used to skip classification on
  // frames that are effectively unusable (lens covered, pitch-dark room).
  // ---------------------------------------------------------------------
  double _averageBrightness(img.Image image) {
    const step = 8;
    var sum = 0.0;
    var count = 0;
    for (var y = 0; y < image.height; y += step) {
      for (var x = 0; x < image.width; x += step) {
        final p = image.getPixel(x, y);
        sum += (p.r + p.g + p.b) / 3.0;
        count++;
      }
    }
    return count == 0 ? 0.0 : sum / count;
  }

  // ---------------------------------------------------------------------
  // Physical flame pixel validator:
  // Fire flames have high red brightness, moderate-to-high green,
  // low blue, and a warm hue (R > G > B). This physically confirms flame
  // presence, eliminating false positives from white lights, ambient
  // sunlight, skin tones, or non-flame warm-colored surfaces.
  // ---------------------------------------------------------------------
  int _countFlamePixels(img.Image image) {
    var count = 0;
    // Step by 2 pixels for speed (112x112 = 12,544 samples on 224x224)
    for (var y = 0; y < image.height; y += 2) {
      for (var x = 0; x < image.width; x += 2) {
        final p = image.getPixel(x, y);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        if (r >= 165 && g >= 55 && r > g && g > b && (r - g) >= 18 && (g - b) >= 12 && b <= 110) {
          count++;
          if (count >= 30) return count; // early exit as soon as threshold is met
        }
      }
    }
    return count;
  }

  // ---------------------------------------------------------------------
  // Preprocessing: resize to targetSize x targetSize (if not already), normalise to [0,1]
  // ---------------------------------------------------------------------
  Float32List _preprocess(img.Image image, int targetSize) {
    final resized = (image.width == targetSize && image.height == targetSize)
        ? image
        : img.copyResize(image, width: targetSize, height: targetSize);
    final buffer = Float32List(targetSize * targetSize * 3);
    var i = 0;
    for (var y = 0; y < targetSize; y++) {
      for (var x = 0; x < targetSize; x++) {
        final pixel = resized.getPixel(x, y);
        buffer[i++] = pixel.r / 255.0;
        buffer[i++] = pixel.g / 255.0;
        buffer[i++] = pixel.b / 255.0;
      }
    }
    return buffer;
  }

  // ---------------------------------------------------------------------
  // Channel-FIRST (NCHW) preprocessing, specifically for the YOLO model.
  // Ultralytics' current LiteRT/TFLite export produces an NCHW input
  // tensor [1, 3, H, W] (verified via interpreter.get_input_details()),
  // unlike the fire/smoke and violence classifiers (Keras-exported,
  // still NHWC [1, H, W, 3]) — so YOLO needs its own layout here.
  // ---------------------------------------------------------------------
  // ignore: unused_element
  List _preprocessNCHW(img.Image image, int targetSize) {
    final resized = img.copyResize(image, width: targetSize, height: targetSize);
    // Build [1, 3, H, W]: channel plane 0 = all R values, plane 1 = all G, plane 2 = all B.
    final channels = List.generate(
      3,
      (c) => List.generate(
        targetSize,
        (y) => List.generate(targetSize, (x) {
          final pixel = resized.getPixel(x, y);
          final v = c == 0 ? pixel.r : (c == 1 ? pixel.g : pixel.b);
          return v / 255.0;
        }),
      ),
    );
    return [channels]; // wrap with the batch dimension -> [1, 3, H, W]
  }

  // ---------------------------------------------------------------------
  // Main entry point — call this once per captured camera frame.
  // Mirrors app.py's POST /predict: runs all 3 checks, logs confirmed
  // events to the local DB, and returns which alerts fired.
  // ---------------------------------------------------------------------
  Future<DetectionResult> analyzeFrame({
    required Uint8List jpegBytes,
    required String cameraId,
    required String location,
  }) async {
    // Drop a busy tick rather than queue stale frames. This also covers
    // initialization and asynchronous event inserts before cooldown is set.
    if (_analyzingFrame) return DetectionResult([]);
    _analyzingFrame = true;
    try {
      return await _analyzeFrame(
        jpegBytes: jpegBytes,
        cameraId: cameraId,
        location: location,
      );
    } finally {
      _analyzingFrame = false;
    }
  }

  Future<DetectionResult> _analyzeFrame({
    required Uint8List jpegBytes,
    required String cameraId,
    required String location,
  }) async {
    final scope = LocalDbService.requireScope();
    if (!identical(_bufferScope, scope)) {
      _fireRollingProbs.clear(); _smokeRollingProbs.clear();
      _violenceBuffers.clear(); _restrictedBuffers.clear(); _lastEventTime.clear();
      _bufferScope = scope;
    }
    if (!_ready) await init();
    scope.checkActive();

    final rawDecoded = img.decodeImage(jpegBytes);
    if (rawDecoded == null) return DetectionResult([]);

    // Android's camera stack saves JPEGs with an EXIF orientation TAG rather
    // than physically rotating the pixel data — photo viewers apply that tag
    // automatically, but a raw decode does not. Without this, every frame fed
    // to the models could be sideways or upside-down relative to the upright
    // photos they were trained on, which alone is enough to produce confused,
    // effectively-random classifications on completely ordinary scenes.
    final decoded = img.bakeOrientation(rawDecoded);

    // ---- DIAGNOSTIC LOGGING (temporary) ----
    // Confirms the JPEG actually decoded to a sane, non-corrupt image, and
    // that pixel channel values are in the expected 0-255 range before the
    // /255.0 normalization — rules out a silent decode failure or an
    // already-normalized/zeroed buffer as the shared cause across models.
    final samplePixel = decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2);
    debugPrint('[DEBUG] decoded size: ${decoded.width}x${decoded.height}, '
        'center pixel raw r/g/b: ${samplePixel.r}/${samplePixel.g}/${samplePixel.b}');

    final confirmed = <Map<String, String>>[];
    final brightness = _averageBrightness(decoded);
    final tooDarkToClassify = brightness < _minBrightnessForClassification;

    if (!tooDarkToClassify) {
      // ---- 1. Fire / Smoke ----
      if (_fireDetectionEnabled) {
        final fireResult = _predictFireSmoke(decoded, cameraId);
        if ((fireResult['fire_confirmed'] as bool) && !_inCooldown(cameraId, 'Fire')) {
          await LocalDbService.insertEvent(
            scope: scope,
            eventType: 'Fire',
            confidence: fireResult['fire_confidence'] as double,
            cameraId: cameraId,
            location: location,
          );
          _markLogged(cameraId, 'Fire');
          confirmed.add({'event_type': 'Fire', 'source': 'fire_model'});
        }
        if (_smokeDetectionEnabledFlag &&
            (fireResult['smoke_confirmed'] as bool) && !_inCooldown(cameraId, 'Smoke')) {
          await LocalDbService.insertEvent(
            scope: scope,
            eventType: 'Smoke',
            confidence: fireResult['smoke_confidence'] as double,
            cameraId: cameraId,
            location: location,
          );
          _markLogged(cameraId, 'Smoke');
          confirmed.add({'event_type': 'Smoke', 'source': 'fire_model'});
        }
        if ((fireResult['fire_confirmed'] as bool) || (fireResult['smoke_confirmed'] as bool)) {
          _fireRollingProbs[cameraId]?.clear();
          _smokeRollingProbs[cameraId]?.clear();
        }
      }

      // ---- 2. Violence ----
      if (_violenceDetectionEnabled) {
        final vioResult = _checkViolence(decoded, cameraId);
        if ((vioResult['violence_confirmed'] as bool) && !_inCooldown(cameraId, 'Violence')) {
          await LocalDbService.insertEvent(
          scope: scope,
            eventType: 'Violence',
            confidence: vioResult['violence_confidence'] as double,
            cameraId: cameraId,
            location: location,
          );
          _violenceBuffers[cameraId]?.clear();
          _markLogged(cameraId, 'Violence');
          confirmed.add({'event_type': 'Violence', 'source': 'violence_model'});
        }
      }
    } else {
      // Frame too dark to classify meaningfully — don't feed garbage
      // predictions into the confirmation buffers at all (a skipped frame
      // is better than a wrong one polluting the rolling average).
    }

    // ---- 3. Restricted zone ----
    // Skip on too-dark frames — the person model produces garbage on
    // pure-black input, causing false "person_in_zone" votes to accumulate
    // in the confirmation buffer and eventually trigger a spurious alert.
    if (tooDarkToClassify) {
      return DetectionResult(confirmed);
    }
    final rzResult = await _checkRestrictedZone(decoded, cameraId, scope);
    if ((rzResult['restricted_zone_alert'] as bool) && !_inCooldown(cameraId, 'Restricted Zone')) {
      await LocalDbService.insertEvent(
          scope: scope,
        eventType: 'Restricted Zone',
        confidence: rzResult['person_confidence'] as double,
        cameraId: cameraId,
        location: location,
      );
      _restrictedBuffers[cameraId]?.clear();
      _markLogged(cameraId, 'Restricted Zone');
      confirmed.add({'event_type': 'Restricted Zone', 'source': 'restricted_zone'});
    }

    return DetectionResult(confirmed);
  }

  // ---------------------------------------------------------------------
  // Fire / Smoke — rolling-average confirmation (mirrors backend detection.py)
  // ---------------------------------------------------------------------
  Map<String, dynamic> _predictFireSmoke(img.Image image, String cameraId) {
    final resized = (image.width == _targetSize && image.height == _targetSize)
        ? image
        : img.copyResize(image, width: _targetSize, height: _targetSize);
    final input = _preprocess(resized, _targetSize).reshape([1, _targetSize, _targetSize, 3]);
    final numClasses = _fireLabels.length;
    final output = List.generate(1, (_) => List.filled(numClasses, 0.0));

    _fireInterpreter!.run(input, output);
    final preds = (output[0] as List).cast<double>();
    debugPrint('[DEBUG] fire raw preds: $preds');

    final fireIdx = _fireLabels.entries.firstWhere((e) => e.value.toLowerCase() == 'fire', orElse: () => const MapEntry('', '')).key;
    final smokeIdx = _fireLabels.entries.firstWhere((e) => e.value.toLowerCase() == 'smoke', orElse: () => const MapEntry('', '')).key;

    final fireProb = fireIdx.isNotEmpty ? preds[int.parse(fireIdx)] : 0.0;
    final smokeProb = smokeIdx.isNotEmpty ? preds[int.parse(smokeIdx)] : 0.0;

    // ---- Fire: rolling probability average ----
    // Every frame's fire probability is appended regardless of which class
    // "won" the argmax — this lets the average naturally drop when fire fades
    // and rise when fire is present, tolerating the occasional Normal flicker
    // that killed the old consecutive-streak approach.
    final fireBuf = _fireRollingProbs.putIfAbsent(cameraId, () => []);
    fireBuf.add(fireProb);
    if (fireBuf.length > _fireBufferSize) fireBuf.removeAt(0);

    final fireRollingAvg = fireBuf.reduce((a, b) => a + b) / fireBuf.length;

    // Physical flame-pixel gate: require actual flame-colored pixels in the
    // CURRENT frame to prevent false positives from warm lighting, orange
    // surfaces, skin tones, etc. that the model may mistake for fire.
    // This is an EXTRA guard the backend doesn't have — strictly safer.
    final flamePixels = _countFlamePixels(resized);

    final fireConfirmed = fireBuf.length >= _fireMinFrames
        && fireRollingAvg >= _fireAvgThreshold
        && flamePixels >= _fireMinFlamePixels;

    debugPrint('[DEBUG] Fire: prob=${fireProb.toStringAsFixed(3)}, '
        'buf=${fireBuf.map((p) => p.toStringAsFixed(2)).toList()}, '
        'avg=${fireRollingAvg.toStringAsFixed(3)}, flamePix=$flamePixels, '
        'confirmed=$fireConfirmed');

    // ---- Smoke: rolling probability average ----
    // No pixel-color gate for smoke (grey/white is too common to be distinctive).
    final smokeBuf = _smokeRollingProbs.putIfAbsent(cameraId, () => []);
    smokeBuf.add(smokeProb);
    if (smokeBuf.length > _smokeBufferSize) smokeBuf.removeAt(0);

    final smokeRollingAvg = smokeBuf.reduce((a, b) => a + b) / smokeBuf.length;

    final smokeConfirmed = smokeBuf.length >= _smokeMinFrames
        && smokeRollingAvg >= _smokeAvgThreshold;

    debugPrint('[DEBUG] Smoke: prob=${smokeProb.toStringAsFixed(3)}, '
        'buf=${smokeBuf.map((p) => p.toStringAsFixed(2)).toList()}, '
        'avg=${smokeRollingAvg.toStringAsFixed(3)}, '
        'confirmed=$smokeConfirmed');

    var maxIdx = 0;
    var maxVal = preds[0];
    for (var i = 1; i < preds.length; i++) {
      if (preds[i] > maxVal) {
        maxVal = preds[i];
        maxIdx = i;
      }
    }

    return {
      'fire_model_result': _fireLabels[maxIdx.toString()] ?? 'class_$maxIdx',
      // Store the class-specific average that confirmed the alert.
      'fire_confidence': fireRollingAvg,
      'fire_confirmed': fireConfirmed,
      'smoke_confidence': smokeRollingAvg,
      'smoke_confirmed': smokeConfirmed,
    };
  }

  // ---------------------------------------------------------------------
  // Violence — mirrors detection.py's check_violence()
  // ---------------------------------------------------------------------
  Map<String, dynamic> _checkViolence(img.Image image, String cameraId) {
    final input = _preprocess(image, _targetSize).reshape([1, _targetSize, _targetSize, 3]);
    final numClasses = _violenceLabels.length;
    final output = List.generate(1, (_) => List.filled(numClasses, 0.0));

    _violenceInterpreter!.run(input, output);
    final preds = (output[0] as List).cast<double>();
    debugPrint('[DEBUG] vio raw preds: $preds');

    var maxIdx = 0;
    var maxVal = preds[0];
    for (var i = 1; i < preds.length; i++) {
      if (preds[i] > maxVal) {
        maxVal = preds[i];
        maxIdx = i;
      }
    }
    final label = _violenceLabels[maxIdx.toString()] ?? 'class_$maxIdx';

    final buf = _violenceBuffers.putIfAbsent(cameraId, () => []);
    buf.add(label);
    if (buf.length > _vioBufferSize) buf.removeAt(0);
    final count = buf.where((l) => l == label).length;
    final confirmed = label.toLowerCase() != 'normal' && maxVal >= _vioMinConfidence && count >= _vioConfirmThreshold;

    return {
      'violence_model_result': label,
      'violence_confidence': maxVal,
      'violence_confirmed': confirmed,
    };
  }

  // ---------------------------------------------------------------------
  // Restricted zone — mirrors detection.py's check_restricted_zone()
  // ---------------------------------------------------------------------
  Future<Map<String, dynamic>> _checkRestrictedZone(img.Image image, String cameraId, LocalDbScope scope) async {
    if (!_personDetectionEnabled) {
      return {'restricted_zone_alert': false, 'person_count': 0, 'person_confidence': 0.0};
    }

    final matchingZones = await LocalDbService.getActiveZonesForCamera(cameraId, scope: scope);
    final inWindow = matchingZones.any(
      (z) => _isWithinWindow(z['start_hour'] as int, z['end_hour'] as int),
    );
    if (!inWindow) {
      // Includes no active matching zone. Votes from an earlier eligible
      // period must not trigger an alert outside its current schedule.
      _restrictedBuffers.remove(cameraId);
      return {'restricted_zone_alert': false, 'person_count': 0, 'person_confidence': 0.0};
    }

    final personConfidence = _detectPersonConfidence(image);
    final rawAlert = personConfidence >= _personConfidenceThreshold;
    final personCount = rawAlert ? 1 : 0;
    final buf = _restrictedBuffers.putIfAbsent(cameraId, () => []);
    buf.add(rawAlert ? 'person_in_zone' : 'clear');
    if (buf.length > _rzBufferSize) buf.removeAt(0);
    final count = buf.where((label) => label == 'person_in_zone').length;
    final confirmed = rawAlert && count >= _rzConfirmThreshold;

    return {
      'restricted_zone_alert': confirmed,
      'person_count': personCount,
      'person_confidence': personConfidence,
    };
  }

  bool _isWithinWindow(int start, int end) {
    final nowHour = DateTime.now().hour;
    if (start < end) {
      return nowHour >= start && nowHour < end;
    } else {
      return nowHour >= start || nowHour < end;
    }
  }

  // ---------------------------------------------------------------------
  // MobileNetV2 person classifier (person_model.tflite).
  // Input: 224x224x3, Output: [no_person, person] softmax.
  // Returns the person class score; this classifier does not count people.
  // ---------------------------------------------------------------------
  double _detectPersonConfidence(img.Image image) {
    final resized = (image.width == _targetSize && image.height == _targetSize)
        ? image
        : img.copyResize(image, width: _targetSize, height: _targetSize);
    // Person model has a built-in Rescaling layer (scale=1/127.5, offset=-1)
    // that expects raw [0, 255] pixel values — do NOT normalize to [0, 1].
    final buffer = Float32List(_targetSize * _targetSize * 3);
    var i = 0;
    for (var y = 0; y < _targetSize; y++) {
      for (var x = 0; x < _targetSize; x++) {
        final pixel = resized.getPixel(x, y);
        buffer[i++] = pixel.r.toDouble();
        buffer[i++] = pixel.g.toDouble();
        buffer[i++] = pixel.b.toDouble();
      }
    }
    final input = buffer.reshape([1, _targetSize, _targetSize, 3]);

    final numClasses = _personLabels.length;
    final output = List.generate(1, (_) => List.filled(numClasses, 0.0));
    _personInterpreter!.run(input, output);

    final preds = (output[0] as List).cast<double>();
    debugPrint('[DEBUG] person raw preds: $preds');

    // Find the person class index
    final personIdx = _personLabels.entries
        .firstWhere((e) => e.value.toLowerCase() == 'person', orElse: () => const MapEntry('-1', ''))
        .key;

    if (personIdx == '-1') return 0.0;
    return preds[int.parse(personIdx)];
  }

  // ---------------------------------------------------------------------
  // Cooldown — mirrors detection.py's is_in_cooldown()/mark_event_logged()
  // ---------------------------------------------------------------------
  bool _inCooldown(String cameraId, String eventType) {
    final key = '$cameraId|$eventType';
    final last = _lastEventTime[key];
    if (last == null) return false;
    return DateTime.now().difference(last).inSeconds < _cooldownSeconds;
  }

  void _markLogged(String cameraId, String eventType) {
    _lastEventTime['$cameraId|$eventType'] = DateTime.now();
  }

  void dispose() {
    _fireInterpreter?.close();
    _violenceInterpreter?.close();
    _personInterpreter?.close();
    _fireInterpreter = null;
    _violenceInterpreter = null;
    _personInterpreter = null;
    _ready = false;
  }
}

extension _ReshapeList on Float32List {
  List reshape(List<int> shape) {
    // tflite_flutter's Interpreter.run accepts nested lists; this flattens
    // our Float32List into the nested structure it expects for a 4D input.
    if (shape.length != 4) throw ArgumentError('Only 4D reshape supported here');
    final b = shape[0], h = shape[1], w = shape[2], c = shape[3];
    var idx = 0;
    return List.generate(b, (_) => List.generate(h, (_) => List.generate(w, (_) => List.generate(c, (_) => this[idx++]))));
  }
}
