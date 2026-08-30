import 'package:flutter/material.dart';
import '../screens/call_screen.dart';
import '../theme/app_theme.dart';

class CallFab extends StatelessWidget {
  final String? orderId;

  const CallFab({super.key, this.orderId});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CallScreen(orderId: orderId)),
      ),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.primary, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.headset_mic_outlined,
            color: AppColors.primary, size: 22),
      ),
    );
  }
}