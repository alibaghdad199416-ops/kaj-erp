import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

class AppPerformance {
  const AppPerformance._();

  static void configure() {
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = kIsWeb ? 160 : 220;
    cache.maximumSizeBytes = kIsWeb ? 72 << 20 : 112 << 20;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      AppLogger.debug('KAJ first frame rendered.');
    });
  }
}
