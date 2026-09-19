import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/push_notification_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class CustomerAuthScreen extends StatefulWidget {
  final bool returnAfterSuccess;

  const CustomerAuthScreen({super.key, this.returnAfterSuccess = false});

  @override
  State<CustomerAuthScreen> createState() => _CustomerAuthScreenState();
}

class _CustomerAuthScreenState extends State<CustomerAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  bool _saving = false;
  bool _loadingProfile = true;
  bool _profileComplete = false;
  bool _otpSent = false;
  int _resendSeconds = 0;
  Timer? _resendTimer;
  String _pendingName = '';
  String _pendingPhone = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _loadingProfile = false);
        return;
      }

      final row = await client
          .from('customers')
          .select('name, phone')
          .eq('id', user.id)
          .maybeSingle();

      final name = (row?['name'] as String?)?.trim() ?? '';
      final phone = (row?['phone'] as String?)?.trim() ?? '';
      final complete =
          name.length >= 2 && RegExp(r'^\+9627\d{8}$').hasMatch(phone);

      if (!mounted) return;
      _nameController.text = name;
      _phoneController.text = phone;
      setState(() {
        _profileComplete = complete;
        _loadingProfile = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _profileComplete = false;
        _loadingProfile = false;
      });
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    final normalizedPhone = _normalizeJordanPhone(_phoneController.text);
    final name = _nameController.text.trim();

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;

      // Keep the anonymous browsing session alive while the SMS is pending.
      // verifyOTP replaces it with the phone-authenticated customer session only
      // after the customer enters the correct code.
      await client.auth.signInWithOtp(
        phone: normalizedPhone,
        shouldCreateUser: true,
      );

      if (!mounted) return;
      _pendingName = name;
      _pendingPhone = normalizedPhone;
      _phoneController.text = normalizedPhone;
      _otpController.clear();
      setState(() {
        _saving = false;
        _otpSent = true;
      });
      _startResendCooldown();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _verifyOtp() async {
    if (_saving) return;
    final code = _otpController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'أدخل رمز التحقق المكوّن من 6 أرقام.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final response = await Supabase.instance.client.auth.verifyOTP(
        phone: _pendingPhone,
        token: code,
        type: OtpType.sms,
      );
      if (response.user == null) {
        throw StateError('تعذر تأكيد رقم الموبايل');
      }

      await SupabaseService.signInAndSaveProfile(
        name: _pendingName,
        phone: _pendingPhone,
      );
      await PushNotificationService.syncCurrentToken();

      if (!mounted) return;
      if (widget.returnAfterSuccess) {
        Navigator.of(context).pop(true);
        return;
      }

      setState(() {
        _saving = false;
        _otpSent = false;
        _profileComplete = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تأكيد رقمك وحفظ بياناتك بنجاح')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(error);
      });
    }
  }

  void _startResendCooldown([int seconds = 60]) {
    _resendTimer?.cancel();
    if (!mounted) return;
    setState(() => _resendSeconds = seconds);

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
        return;
      }
      setState(() => _resendSeconds -= 1);
    });
  }

  Future<void> _resendOtp() async {
    if (_saving || _pendingPhone.isEmpty || _resendSeconds > 0) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        phone: _pendingPhone,
        shouldCreateUser: true,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      _startResendCooldown();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم إرسال رمز جديد')));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(error);
      });
    }
  }

  String _normalizeJordanPhone(String input) {
    var value = input.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    if (value.startsWith('00962')) {
      value = '+962${value.substring(5)}';
    } else if (value.startsWith('962')) {
      value = '+$value';
    } else if (value.startsWith('07') && value.length == 10) {
      value = '+962${value.substring(1)}';
    }

    return value;
  }

  bool _isValidJordanPhone(String input) {
    final value = _normalizeJordanPhone(input);
    return RegExp(r'^\+9627\d{8}$').hasMatch(value);
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    final lower = text.toLowerCase();

    if (lower.contains('network') || lower.contains('socketexception')) {
      return 'تعذر الاتصال بالإنترنت. تأكد من الشبكة وحاول مرة ثانية.';
    }
    if (lower.contains('rate') || lower.contains('too many')) {
      return 'تم طلب رموز كثيرة خلال وقت قصير. انتظر قليلًا ثم حاول مرة ثانية.';
    }
    if (lower.contains('token') ||
        lower.contains('otp') ||
        lower.contains('expired')) {
      return 'رمز التحقق غير صحيح أو انتهت صلاحيته. اطلب رمزًا جديدًا.';
    }
    if (lower.contains('sms') || lower.contains('provider')) {
      return 'خدمة رسائل التحقق غير مفعّلة حاليًا. تواصل مع إدارة المول.';
    }

    return text.replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');
  }

  void _changeNumber() {
    setState(() {
      _otpSent = false;
      _otpController.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingProfile) {
      return Scaffold(
        appBar: AppBar(title: const Text('بيانات الحساب')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_profileComplete) {
      return Scaffold(
        appBar: AppBar(title: const Text('بيانات الحساب')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 34,
                  backgroundColor: AppColors.skySoft,
                  child: Icon(
                    Icons.verified_user_outlined,
                    size: 34,
                    color: AppColors.skyBlueDark,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _nameController.text,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _phoneController.text,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 20),
                if (widget.returnAfterSuccess)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('متابعة لإتمام الطلب'),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _profileComplete = false),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('تعديل الاسم أو رقم الموبايل'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    if (_otpSent) {
      return Scaffold(
        appBar: AppBar(title: const Text('تأكيد رقم الموبايل')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  child: Container(
                    width: 74,
                    height: 74,
                    decoration: const BoxDecoration(
                      color: AppColors.skySoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.sms_outlined,
                      color: AppColors.skyBlueDark,
                      size: 34,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'أرسلنا لك رمز تحقق',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 7),
                Text(
                  'أدخل الرمز المرسل إلى $_pendingPhone. هذه الخطوة مطلوبة أول مرة فقط.',
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 26),
                TextField(
                  controller: _otpController,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 8,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'رمز التحقق',
                    hintText: '000000',
                  ),
                  onSubmitted: (_) => _verifyOtp(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _ErrorBox(text: _error!),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _saving ? null : _verifyOtp,
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text('تأكيد ومتابعة'),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _saving || _resendSeconds > 0
                          ? null
                          : _resendOtp,
                      child: Text(
                        _resendSeconds > 0
                            ? 'إعادة الإرسال بعد ${_resendSeconds}ث'
                            : 'إرسال الرمز مرة ثانية',
                      ),
                    ),
                    TextButton(
                      onPressed: _saving ? null : _changeNumber,
                      child: const Text('تغيير الرقم'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('بيانات الحساب')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.shopping_bag_outlined,
                  size: 54,
                  color: AppColors.skyBlueDark,
                ),
                const SizedBox(height: 12),
                const Text(
                  'قبل ما نكمل الطلب',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'اكتب اسمك ورقم موبايلك. سنرسل رمز OTP لتأكيد الرقم أول مرة فقط.',
                  textAlign: TextAlign.center,
                  style: TextStyle(height: 1.5, color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 26),
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(
                    labelText: 'الاسم',
                    hintText: 'مثال: محمد أحمد',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) {
                    final normalized = value?.trim() ?? '';
                    if (normalized.length < 2) return 'اكتب الاسم';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[0-9+\-\s\(\)]'),
                    ),
                  ],
                  onFieldSubmitted: (_) => _sendOtp(),
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'رقم الموبايل',
                    hintText: '07XXXXXXXX',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (value) {
                    final normalized = value?.trim() ?? '';
                    if (normalized.isEmpty) return 'اكتب رقم الموبايل';
                    if (!_isValidJordanPhone(normalized)) {
                      return 'أدخل رقم أردني صحيح مثل 0791234567';
                    }
                    return null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _ErrorBox(text: _error!),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _sendOtp,
                    icon: const Icon(Icons.sms_outlined),
                    label: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Text('إرسال رمز التحقق'),
                  ),
                ),
                const SizedBox(height: 12),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: Color(0xFF6B7280),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'بعد تأكيد الرقم لن نطلب OTP في كل مرة على نفس الحساب والجهاز.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String text;

  const _ErrorBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF9F1239),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
