import 'package:flutter_test/flutter_test.dart';
import 'package:edumesh_android/core/models/resource_model.dart';

void main() {
  test('dynamic dispatch of enum name getter', () {
    final m = ResourceModel(
      id: '1', title: 't', subject: 's', grade: '1', type: ResourceType.videos,
    );
    final dynamic original = m;
    expect(original.type, ResourceType.videos);
    expect(original.type.name, 'videos');
  });
}
