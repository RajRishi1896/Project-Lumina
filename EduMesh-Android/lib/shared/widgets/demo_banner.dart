import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../features/auth/data/auth_service.dart';

class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        border: Border(bottom: BorderSide(color: cs.primary.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          Icon(Icons.science_rounded, size: 14.sp, color: cs.primary),
          SizedBox(width: 6.w),
          Text('Demo Mode',
              style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                  letterSpacing: 0.5)),
          SizedBox(width: 8.w),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 1.h),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              AuthService.isDemoAdmin() ? 'Admin' : 'Student',
              style: TextStyle(fontSize: 9.sp, color: cs.primary, fontWeight: FontWeight.w500),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => _showInfo(context),
            child: Icon(Icons.info_outline, size: 14.sp, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  void _showInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.science_rounded, color: Theme.of(context).colorScheme.primary),
            SizedBox(width: 8.w),
            const Text('Demo Mode'),
          ],
        ),
        content: const Text(
          'You are viewing EduMesh in Demo Mode.\n\n'
          '• All features are fully accessible\n'
          '• Role can be toggled in Settings\n'
          '• Demo data can be loaded per tab\n'
          '• Perfect for exploration and testing',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it')),
        ],
      ),
    );
  }
}
