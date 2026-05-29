import 'package:flutter/material.dart';

import 'package:edumesh_android/core/models/resource_model.dart';
import 'package:edumesh_android/features/dashboard/presentation/resource_list_page.dart';

class AppNavigator {
  static void openResources(
    BuildContext context, {
    required ResourceType type,
    String? grade,
    String? subject,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ResourcePage(
          subject: subject ?? 'General',
          grade: grade ?? 'All',
        ),
      ),
    );
  }
}