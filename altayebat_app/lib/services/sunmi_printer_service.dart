import 'package:flutter/services.dart';

class SunmiPrinterService {
  SunmiPrinterService._();

  static const MethodChannel _channel = MethodChannel(
    'com.altayebat.app/sunmi_printer',
  );

  static Future<bool> isSunmiDevice() async {
    try {
      return await _channel.invokeMethod<bool>('isSunmiDevice') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> isPrinterReady() async {
    try {
      return await _channel.invokeMethod<bool>('isPrinterReady') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<Map<String, dynamic>> printerInfo() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'printerInfo',
      );
      return Map<String, dynamic>.from(result ?? const {});
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      return const {};
    }
  }

  static Future<void> printReceipt({
    required String receipt,
    String? qr,
  }) async {
    final printed = await _channel.invokeMethod<bool>(
      'printReceipt',
      <String, dynamic>{'receipt': receipt, 'qr': qr ?? ''},
    );
    if (printed != true) {
      throw StateError('تعذر إرسال الفاتورة للطابعة');
    }
  }

  static Future<void> printTest() async {
    final printed = await _channel.invokeMethod<bool>('printTest');
    if (printed != true) {
      throw StateError('تعذر طباعة صفحة الاختبار');
    }
  }
}
