import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service managing system-wide floating overlay across the entire Android device.
/// Operates via Android SYSTEM_ALERT_WINDOW and OverlayBubbleService.
class SystemOverlayService {
  static const MethodChannel _channel = MethodChannel('com.nirikshak.overlay');

  static final List<VoidCallback> _circleToSearchListeners = [];
  static final List<Function(String imagePath)> _snipSubmittedListeners = [];
  static final List<Function(List<String> imagePaths)> _reviewSubmittedListeners = [];
  static bool _initialized = false;

  /// Initializes MethodChannel listener for external overlay triggers.
  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onCircleToSearchTriggered') {
        debugPrint('[SystemOverlayService] Circle to search triggered from external overlay!');
        for (final listener in List<VoidCallback>.from(_circleToSearchListeners)) {
          try {
            listener();
          } catch (e) {
            debugPrint('[SystemOverlayService] Error invoking circle-to-search listener: $e');
          }
        }
      } else if (call.method == 'onSnipSubmitted') {
        final Map? args = call.arguments as Map?;
        final String? imagePath = args?['image_path'] as String?;
        if (imagePath != null && imagePath.isNotEmpty) {
          debugPrint('[SystemOverlayService] Snip submitted from overlay: $imagePath');
          for (final listener in List<Function(String)>.from(_snipSubmittedListeners)) {
            try {
              listener(imagePath);
            } catch (e) {
              debugPrint('[SystemOverlayService] Error invoking snip listener: $e');
            }
          }
        }
      } else if (call.method == 'onReviewSubmitted') {
        final Map? args = call.arguments as Map?;
        final List? rawPaths = args?['image_paths'] as List?;
        if (rawPaths != null && rawPaths.isNotEmpty) {
          final List<String> paths = rawPaths.map((e) => e.toString()).toList();
          debugPrint('[SystemOverlayService] Review submitted with ${paths.length} angles: $paths');
          for (final listener in List<Function(List<String>)>.from(_reviewSubmittedListeners)) {
            try {
              listener(paths);
            } catch (e) {
              debugPrint('[SystemOverlayService] Error invoking review listener: $e');
            }
          }
        }
      }
    });
  }

  /// Adds a listener for when user taps the floating bubble from outside or inside.
  static void addCircleToSearchListener(VoidCallback listener) {
    initialize();
    if (!_circleToSearchListeners.contains(listener)) {
      _circleToSearchListeners.add(listener);
    }
  }

  /// Removes a registered listener.
  static void removeCircleToSearchListener(VoidCallback listener) {
    _circleToSearchListeners.remove(listener);
  }

  /// Adds a listener for when a snip is circled and submitted from the overlay.
  static void addSnipSubmittedListener(Function(String imagePath) listener) {
    initialize();
    if (!_snipSubmittedListeners.contains(listener)) {
      _snipSubmittedListeners.add(listener);
    }
  }

  /// Removes a registered snip listener.
  static void removeSnipSubmittedListener(Function(String imagePath) listener) {
    _snipSubmittedListeners.remove(listener);
  }

  /// Adds a listener for when user taps 'Proceed to Review' with multiple staged angles.
  static void addReviewSubmittedListener(Function(List<String> imagePaths) listener) {
    initialize();
    if (!_reviewSubmittedListeners.contains(listener)) {
      _reviewSubmittedListeners.add(listener);
    }
  }

  /// Removes a registered review listener.
  static void removeReviewSubmittedListener(Function(List<String> imagePaths) listener) {
    _reviewSubmittedListeners.remove(listener);
  }

  /// Checks if SYSTEM_ALERT_WINDOW overlay permission is granted by the user.
  static Future<bool> isPermissionGranted() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool granted = await _channel.invokeMethod('isPermissionGranted') ?? false;
      return granted;
    } on PlatformException catch (e) {
      debugPrint('[SystemOverlayService] isPermissionGranted error: $e');
      return false;
    }
  }

  /// Requests SYSTEM_ALERT_WINDOW overlay permission via Android Settings.
  static Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool res = await _channel.invokeMethod('requestPermission') ?? false;
      return res;
    } on PlatformException catch (e) {
      debugPrint('[SystemOverlayService] requestPermission error: $e');
      return false;
    }
  }

  /// Requests MediaProjection permission to capture the screen during Circle-to-Search.
  static Future<bool> requestScreenCapturePermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool res = await _channel.invokeMethod('requestScreenCapturePermission') ?? false;
      return res;
    } on PlatformException catch (e) {
      debugPrint('[SystemOverlayService] requestScreenCapturePermission error: $e');
      return false;
    }
  }

  /// Checks if screen capture projection token is ready.
  static Future<bool> isScreenCaptureReady() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool ready = await _channel.invokeMethod('isScreenCaptureReady') ?? false;
      return ready;
    } on PlatformException catch (e) {
      debugPrint('[SystemOverlayService] isScreenCaptureReady error: $e');
      return false;
    }
  }

  /// Starts the system-wide floating overlay bubble showing the Nirikshak logo.
  static Future<bool> startOverlay() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool res = await _channel.invokeMethod('startOverlay') ?? false;
      return res;
    } on PlatformException catch (e) {
      debugPrint('[SystemOverlayService] startOverlay error: $e');
      return false;
    }
  }

  /// Stops the system-wide floating overlay bubble.
  static Future<bool> stopOverlay() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool res = await _channel.invokeMethod('stopOverlay') ?? false;
      return res;
    } on PlatformException catch (e) {
      debugPrint('[SystemOverlayService] stopOverlay error: $e');
      return false;
    }
  }

  /// Checks if the foreground overlay service is currently running.
  static Future<bool> isOverlayRunning() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool running = await _channel.invokeMethod('isOverlayRunning') ?? false;
      return running;
    } on PlatformException catch (e) {
      debugPrint('[SystemOverlayService] isOverlayRunning error: $e');
      return false;
    }
  }
}
