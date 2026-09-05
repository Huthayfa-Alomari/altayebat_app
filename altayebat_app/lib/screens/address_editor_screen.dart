import 'package:flutter/material.dart';

import '../models/customer_address.dart';
import '../models/picked_location.dart';
import '../services/supabase_service.dart';
import 'location_picker_screen.dart';

class AddressEditorScreen extends StatefulWidget {
  final CustomerAddress? address;
  final bool makeDefault;

  const AddressEditorScreen({
    super.key,
    this.address,
    this.makeDefault = false,
  });

  @override
  State<AddressEditorScreen> createState() => _AddressEditorScreenState();
}

class _AddressEditorScreenState extends State<AddressEditorScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _label;
  late final TextEditingController _city;
  late final TextEditingController _area;
  late final TextEditingController _street;
  late final TextEditingController _building;
  late final TextEditingController _floor;
  late final TextEditingController _notes;

  PickedLocation? _location;
  Map<String, dynamic>? _coverage;
  bool _checkingCoverage = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final address = widget.address;

    _label = TextEditingController(text: address?.label ?? 'البيت');
    _city = TextEditingController(text: address?.city ?? '');
    _area = TextEditingController(text: address?.area ?? '');
    _street = TextEditingController(text: address?.street ?? '');
    _building = TextEditingController(text: address?.building ?? '');
    _floor = TextEditingController(text: address?.floor ?? '');
    _notes = TextEditingController(text: address?.notes ?? '');

    if (address?.latitude != null && address?.longitude != null) {
      _location = PickedLocation(
        latitude: address!.latitude!,
        longitude: address.longitude!,
        accuracyMeters: address.accuracyMeters,
        source: address.locationSource ?? 'map',
      );
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _city.dispose();
    _area.dispose();
    _street.dispose();
    _building.dispose();
    _floor.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialLatitude: _location?.latitude,
          initialLongitude: _location?.longitude,
        ),
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      _location = result;
      _coverage = null;
      _error = null;
    });

    await _checkCoverage();
  }

  Future<void> _checkCoverage() async {
    final location = _location;
    if (location == null) return;

    setState(() {
      _checkingCoverage = true;
      _error = null;
    });

    try {
      final result = await SupabaseService.getDeliveryServiceability(
        latitude: location.latitude,
        longitude: location.longitude,
        city: _city.text,
        area: _area.text,
      );
      if (!mounted) return;
      setState(() => _coverage = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _checkingCoverage = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final current = widget.address;
      late CustomerAddress saved;

      if (current == null) {
        saved = await SupabaseService.createAddress(
          label: _label.text,
          city: _city.text,
          area: _area.text,
          street: _street.text,
          building: _building.text,
          floor: _floor.text,
          notes: _notes.text,
          latitude: _location?.latitude,
          longitude: _location?.longitude,
          accuracyMeters: _location?.accuracyMeters,
          locationSource: _location?.source ?? 'manual',
          isDefault: widget.makeDefault,
        );
      } else {
        saved = await SupabaseService.updateAddress(
          addressId: current.id,
          label: _label.text,
          city: _city.text,
          area: _area.text,
          street: _street.text,
          building: _building.text,
          floor: _floor.text,
          notes: _notes.text,
          latitude: _location?.latitude,
          longitude: _location?.longitude,
          accuracyMeters: _location?.accuracyMeters,
          locationSource: _location?.source ?? 'manual',
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _message(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Exception: ', '');

  @override
  Widget build(BuildContext context) {
    final serviceable = _coverage?['serviceable'] == true;
    final deliveryFee = _coverage?['delivery_fee'];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.address == null ? 'إضافة عنوان' : 'تعديل العنوان'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
          children: [
            _SectionCard(
              title: 'الموقع',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickLocation,
                    icon: Icon(
                      _location == null
                          ? Icons.location_on_outlined
                          : Icons.location_on,
                    ),
                    label: Text(
                      _location == null
                          ? 'حدد موقع البيت على الخريطة'
                          : 'تم تحديد الموقع — اضغط للتعديل',
                    ),
                  ),
                  if (_checkingCoverage)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: LinearProgressIndicator(),
                    ),
                  if (_coverage != null)
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: serviceable
                            ? const Color(0xFFF0FDF4)
                            : const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            serviceable
                                ? Icons.check_circle_outline
                                : Icons.cancel_outlined,
                            color: serviceable
                                ? const Color(0xFF15803D)
                                : const Color(0xFFBE123C),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              serviceable
                                  ? 'التوصيل متاح${deliveryFee == null ? '' : ' — الرسوم $deliveryFee د.أ'}'
                                  : 'الموقع خارج مناطق التوصيل الحالية',
                              style: TextStyle(
                                color: serviceable
                                    ? const Color(0xFF166534)
                                    : const Color(0xFF9F1239),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'تفاصيل العنوان',
              child: Column(
                children: [
                  TextFormField(
                    controller: _label,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'اسم العنوان',
                      hintText: 'البيت / العمل',
                      prefixIcon: Icon(Icons.bookmark_border),
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'اكتب اسمًا للعنوان'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _city,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'المدينة',
                            hintText: 'الزرقاء',
                          ),
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? 'اكتب المدينة'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _area,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'المنطقة',
                            hintText: 'اسم الحي',
                          ),
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? 'اكتب المنطقة'
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _street,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'الشارع (اختياري)',
                      prefixIcon: Icon(Icons.signpost_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _building,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'رقم البناية',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _floor,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'الطابق',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _notes,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات للسائق (اختياري)',
                      hintText: 'معلم قريب أو تفاصيل تساعد السائق',
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _ErrorBox(message: _error!),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('حفظ العنوان'),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;

  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, style: const TextStyle(color: Color(0xFF9F1239))),
    );
  }
}
