import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DeviceBrand { tecno, infinix, xiaomi, samsung, other }

class ManufacturerGuidance {
  final String brandName;
  final String osSkin;
  final List<String> steps;

  const ManufacturerGuidance({
    required this.brandName,
    required this.osSkin,
    required this.steps,
  });
}

/// Service managing Android battery optimization exemptions and low-memory killer survival
class DeviceHealthService {
  static const MethodChannel _batteryChannel = MethodChannel('com.swbudget/battery');

  /// Check if the app is currently whitelisted from battery restrictions
  Future<bool> isBatteryOptimizationIgnored() async {
    try {
      final bool? isIgnored =
          await _batteryChannel.invokeMethod<bool>('isBatteryOptimizationIgnored');
      return isIgnored ?? false;
    } on MissingPluginException catch (_) {
      return true; // Non-Android / desktop / test harness
    } catch (_) {
      return false;
    }
  }

  /// Request system prompt to ignore battery optimizations
  Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      final bool? success =
          await _batteryChannel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      return success ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Identify device manufacturer brand
  Future<DeviceBrand> getDeviceBrand() async {
    try {
      final String? manufacturer =
          await _batteryChannel.invokeMethod<String>('getDeviceManufacturer');
      final clean = (manufacturer ?? '').toUpperCase();

      if (clean.contains('TECNO')) return DeviceBrand.tecno;
      if (clean.contains('INFINIX') || clean.contains('ITEL') || clean.contains('TRANSSION')) {
        return DeviceBrand.infinix;
      }
      if (clean.contains('XIAOMI') || clean.contains('REDMI') || clean.contains('POCO')) {
        return DeviceBrand.xiaomi;
      }
      if (clean.contains('SAMSUNG')) return DeviceBrand.samsung;
      return DeviceBrand.other;
    } catch (_) {
      return DeviceBrand.other;
    }
  }

  /// Get manufacturer-specific survival instructions
  ManufacturerGuidance getGuidanceForBrand(DeviceBrand brand) {
    switch (brand) {
      case DeviceBrand.tecno:
      case DeviceBrand.infinix:
        return const ManufacturerGuidance(
          brandName: 'Tecno / Infinix',
          osSkin: 'HiOS / XOS Battery Lab',
          steps: [
            'Open phone Settings -> Battery Lab.',
            'Select "App Battery Management" and find SW-budget.',
            'Set to "No restrictions".',
            'In "Auto-start Management", toggle SW-budget to Allowed.',
          ],
        );
      case DeviceBrand.xiaomi:
        return const ManufacturerGuidance(
          brandName: 'Xiaomi / Redmi',
          osSkin: 'MIUI / HyperOS Security',
          steps: [
            'Open phone Settings -> Apps -> Manage Apps -> SW-budget.',
            'Toggle "Autostart" to ON.',
            'Under "Battery Saver", change selection to "No restrictions".',
            'Lock SW-budget in recent apps view.',
          ],
        );
      case DeviceBrand.samsung:
        return const ManufacturerGuidance(
          brandName: 'Samsung Galaxy',
          osSkin: 'One UI Device Care',
          steps: [
            'Open Settings -> Battery and device care -> Battery.',
            'Tap "Background usage limits".',
            'Select "Never sleeping apps" and add SW-budget.',
          ],
        );
      case DeviceBrand.other:
        return const ManufacturerGuidance(
          brandName: 'Android Device',
          osSkin: 'Standard Battery Optimization',
          steps: [
            'Tap "Grant Exemption" below.',
            'Select "Allow" on the system prompt so SW-budget can record incoming bank SMS in the background.',
          ],
        );
    }
  }

  /// Start foreground sync service for high-volume historical message imports
  Future<void> startForegroundSync({int totalCount = 0}) async {
    try {
      await _batteryChannel.invokeMethod('startForegroundSync', {'totalCount': totalCount});
    } catch (_) {}
  }

  /// Stop foreground sync service
  Future<void> stopForegroundSync() async {
    try {
      await _batteryChannel.invokeMethod('stopForegroundSync');
    } catch (_) {}
  }

  /// Open Android Notification Access settings so user can authorize banking app notification listening
  Future<bool> openNotificationAccessSettings() async {
    try {
      final bool? success =
          await _batteryChannel.invokeMethod<bool>('openNotificationAccessSettings');
      return success ?? false;
    } catch (_) {
      return false;
    }
  }
}

final deviceHealthServiceProvider = Provider<DeviceHealthService>((ref) {
  return DeviceHealthService();
});

