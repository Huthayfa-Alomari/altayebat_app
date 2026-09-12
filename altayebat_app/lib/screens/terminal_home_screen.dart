import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/sunmi_printer_service.dart';
import 'terminal_inventory_screen.dart';
import 'terminal_orders_screen.dart';

class TerminalHomeScreen extends StatefulWidget {
  final VoidCallback onSignedOut;

  const TerminalHomeScreen({super.key, required this.onSignedOut});

  @override
  State<TerminalHomeScreen> createState() => _TerminalHomeScreenState();
}

class _TerminalHomeScreenState extends State<TerminalHomeScreen> {
  int _index = 0;
  late Future<Map<String, dynamic>> _printerInfo;

  @override
  void initState() {
    super.initState();
    _printerInfo = SunmiPrinterService.printerInfo();
  }

  Future<void> _testPrinter() async {
    try {
      await SunmiPrinterService.printTest();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال صفحة الاختبار للطابعة.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('PlatformException(', '').replaceFirst('Bad state: ', ''),
          ),
        ),
      );
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    widget.onSignedOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_index == 0 ? 'طلبات الطيبات' : 'الجرد والباركود'),
        actions: [
          FutureBuilder<Map<String, dynamic>>(
            future: _printerInfo,
            builder: (context, snapshot) {
              final ready = snapshot.data?['ready'] == true;
              return IconButton(
                tooltip: ready ? 'طابعة SUNMI جاهزة — اختبار' : 'الطابعة غير متصلة',
                onPressed: ready ? _testPrinter : () => setState(() {
                  _printerInfo = SunmiPrinterService.printerInfo();
                }),
                icon: Icon(
                  ready ? Icons.print_rounded : Icons.print_disabled_outlined,
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') _signOut();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'logout', child: Text('تسجيل الخروج')),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          TerminalOrdersScreen(),
          TerminalInventoryScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'الطلبات',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_outlined),
            selectedIcon: Icon(Icons.qr_code_scanner_rounded),
            label: 'الجرد',
          ),
        ],
      ),
    );
  }
}
