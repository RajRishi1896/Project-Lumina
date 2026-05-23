import 'package:flutter/material.dart';
import 'package:edumesh_android/core/models/resource_model.dart';
import 'package:edumesh_android/shared/services/mock_data_service.dart';

class SaveResourceService {
  /// Toggles the saved status of a resource by ID.
  static Future<bool> toggleSaveStatus(String id) async {
    try {
      final List<ResourceModel> liveResources = MockDataService.getResources();
      final item = liveResources.firstWhere((r) => r.id == id);
      item.isDownloaded = !item.isDownloaded;
      return true;
    } catch (e) {
      debugPrint("Error toggling save status: $e");
      return false;
    }
  }

  /// Helper to get all currently saved resources.
  static Future<List<ResourceModel>> getAllSavedResources() async {
    final all = MockDataService.getResources();
    return all.where((r) => r.isDownloaded).toList();
  }

  /// Helper to check if a specific item is saved.
  static Future<bool> isSaved(String id) async {
    final all = MockDataService.getResources();
    try {
      return all.firstWhere((r) => r.id == id).isDownloaded;
    } catch (e) {
      return false;
    }
  }

  /// Helper to get saved resources filtered by the ResourceType enum.
  static Future<List<ResourceModel>> getSavedByType(ResourceType type) async {
    final all = await getAllSavedResources();
    // Compare directly with the enum - no need for .toLowerCase()!
    return all.where((r) => r.type == type).toList();
  }
}