import 'package:flutter/material.dart';

import 'package:edumesh_android/core/models/resource_model.dart';
// Check this import at the top of app_navigator.dart
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
        builder: (context) => ResourceListPage(
          type: type,
          title: '$subject ${type.name.toUpperCase()}',
          grade: grade,
          subject: subject,
        ),
      ),
    );
  }
}