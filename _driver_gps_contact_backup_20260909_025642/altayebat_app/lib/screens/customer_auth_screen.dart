import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/supabase_service.dart';

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

  bool _saving = false;
  String? _error;

  bool get _alreadySignedIn => SupabaseService.isSignedIn;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await SupabaseService.signInAndSaveProfile(
        name: _nameController.text.trim(),
        phone: _normalizeJordanPhone(_phoneController.text),
      );

      if (!mounted) return;

      if (widget.returnAfterSuccess) {
        Navigator.of(context).pop(true);
        return;
      }

      setState(() => _saving = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حفظ بياناتك بنجاح')));
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

    if (text.contains('network') || text.contains('SocketException')) {
      return 'تعذر الاتصال بالإنترنت. تأكد من الشبكة وحاول مرة ثانية.';
    }

    return text.replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    if (_alreadySignedIn) {
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
                  child: Icon(Icons.person, size: 34),
                ),
                const SizedBox(height: 16),
                const Text(
                  'بياناتك محفوظة',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'تقدر تكمل التسوق والطلب مباشرة.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 20),
                if (widget.returnAfterSuccess)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('متابعة لإتمام الطلب'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل بياناتك')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.shopping_bag_outlined, size: 54),
                const SizedBox(height: 12),
                const Text(
                  'قبل ما نكمل الطلب',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'اكتب اسمك ورقم موبايلك فقط. ما في كلمة مرور ولا خطوات معقدة.',
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
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final normalized = value?.trim() ?? '';
                    if (normalized.length < 2) {
                      return 'اكتب الاسم';
                    }
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
                  onFieldSubmitted: (_) => _submit(),
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'رقم الموبايل',
                    hintText: '07XXXXXXXX',
                    prefixIcon: Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final normalized = value?.trim() ?? '';
                    if (normalized.isEmpty) {
                      return 'اكتب رقم الموبايل';
                    }
                    if (!_isValidJordanPhone(normalized)) {
                      return 'أدخل رقم أردني صحيح مثل 0791234567';
                    }
                    return null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF9F1239),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : Text(
                            widget.returnAfterSuccess
                                ? 'حفظ ومتابعة للطلب'
                                : 'حفظ بياناتي',
                          ),
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
                        'نستخدم هذه البيانات للتواصل بخصوص الطلب والتوصيل فقط.',
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
