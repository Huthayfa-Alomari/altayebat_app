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

  bool get _isEditing => widget.address != null;

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
    FocusScope.of(context).unfocus();
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
    FocusScope.of(context).unfocus();
    if (_saving || !_formKey.currentState!.validate()) return;

    if (_location == null) {
      await _pickLocation();
      if (!mounted) return;
      if (_location == null) {
        setState(() {
          _error = 'حدد موقع التوصيل على الخريطة حتى يصل المندوب بدقة.';
        });
        return;
      }
    }

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
    final theme = Theme.of(context);
    final serviceable = _coverage?['serviceable'] == true;
    final deliveryFee = _coverage?['delivery_fee'];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'تعديل العنوان' : 'عنوان التوصيل'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 150),
          children: [
            _StepCard(
              number: '1',
              title: 'حدد مكانك',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 56,
                    child: FilledButton.tonalIcon(
                      onPressed: _pickLocation,
                      icon: Icon(
                        _location == null
                            ? Icons.location_on_outlined
                            : Icons.location_on_rounded,
                      ),
                      label: Text(
                        _location == null
                            ? 'حدد موقعك على الخريطة'
                            : 'تم تحديد الموقع — اضغط للتعديل',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  if (_checkingCoverage) ...[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(),
                  ],
                  if (_coverage != null) ...[
                    const SizedBox(height: 10),
                    _CoverageMessage(
                      serviceable: serviceable,
                      deliveryFee: deliveryFee,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            _StepCard(
              number: '2',
              title: 'اكتب العنوان',
              child: Column(
                children: [
                  TextFormField(
                    controller: _label,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'اسم العنوان',
                      hintText: 'البيت أو العمل',
                      prefixIcon: Icon(Icons.bookmark_border_rounded),
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'اكتب اسمًا للعنوان'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _city,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'المدينة',
                      hintText: 'مثال: الزرقاء',
                      prefixIcon: Icon(Icons.location_city_outlined),
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'اكتب المدينة'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _area,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'المنطقة أو الحي',
                      hintText: 'مثال: حي الأمير محمد',
                      prefixIcon: Icon(Icons.map_outlined),
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'اكتب المنطقة'
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                leading: Icon(
                  Icons.add_circle_outline_rounded,
                  color: theme.colorScheme.primary,
                ),
                title: const Text(
                  'تفاصيل إضافية',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'اختياري — شارع، بناية، طابق أو ملاحظة للسائق',
                  style: TextStyle(fontSize: 12),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                children: [
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
                            labelText: 'البناية',
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
                      labelText: 'ملاحظة للسائق (اختياري)',
                      hintText: 'مثال: بجانب الصيدلية',
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              _ErrorBox(message: _error!),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Material(
          color: theme.colorScheme.surface,
          elevation: 12,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 21,
                        height: 21,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(
                  _saving
                      ? 'جاري الحفظ...'
                      : _isEditing
                      ? 'حفظ التعديلات'
                      : 'حفظ واستخدام العنوان',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final String number;
  final String title;
  final Widget child;

  const _StepCard({
    required this.number,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    number,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _CoverageMessage extends StatelessWidget {
  final bool serviceable;
  final dynamic deliveryFee;

  const _CoverageMessage({
    required this.serviceable,
    required this.deliveryFee,
  });

  @override
  Widget build(BuildContext context) {
    final background = serviceable
        ? const Color(0xFFF0FDF4)
        : const Color(0xFFFFF1F2);
    final foreground = serviceable
        ? const Color(0xFF166534)
        : const Color(0xFF9F1239);

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            serviceable
                ? Icons.check_circle_outline_rounded
                : Icons.info_outline_rounded,
            color: foreground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              serviceable
                  ? 'التوصيل متاح${deliveryFee == null ? '' : ' — الرسوم $deliveryFee د.أ'}'
                  : 'الموقع خارج مناطق التوصيل الحالية',
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
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
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFF9F1239)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF9F1239),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
