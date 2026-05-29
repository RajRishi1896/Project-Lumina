import 'package:dio/dio.dart';

class DemoData {
  /// Returns a Dio Response with mock data matching the given API path.
  /// Returns null if the path is not recognized (caller falls through to real request).
  static Response<T>? response<T>(String path, Map<String, dynamic>? queryParams) {
    // Match path and return appropriate mock data
    final data = _mockFor(path, queryParams);
    if (data == null) return null;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: data as T,
      statusCode: 200,
    );
  }

  static dynamic _mockFor(String path, Map<String, dynamic>? queryParams) {
    // Remove trailing slashes and split
    final p = path.replaceAll(RegExp(r'/+$'), '');
    
    // --- Student endpoints ---
    if (p == '/ping') return {'status': 'pong'};
    
    if (p == '/register') return {'id': 'LUMINA_01-DEMO${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}'};
    
    if (p == '/student/token') return {
      'status': 'success',
      'scholar_id': 'LUMINA_01-DEMOSCHOLAR',
      'username': 'demo_student',
      'reset_required': 0,
    };
    
    if (p == '/student/change-password') return {'status': 'success'};
    
    if (p.startsWith('/student/')) return {'status': 'ok'};
    
    // --- Catalog / Resources ---
    if (p == '/api/catalog' || p == '/resources') return [
      {'id': 101, 'title': 'Algebra Fundamentals', 'url': '/files/algebra.pdf', 'type': 'textbook', 'subject': 'Mathematics'},
      {'id': 102, 'title': 'Newtonian Mechanics', 'url': '/files/mechanics.pdf', 'type': 'textbook', 'subject': 'Physics'},
      {'id': 103, 'title': 'Organic Chemistry Reactions', 'url': '/files/organic_chem.mp4', 'type': 'videos', 'subject': 'Chemistry'},
      {'id': 104, 'title': 'Cell Biology Notes', 'url': '/files/cell_bio.pdf', 'type': 'notes', 'subject': 'Biology'},
      {'id': 105, 'title': 'World War II Overview', 'url': '/files/ww2.pdf', 'type': 'textbook', 'subject': 'History'},
      {'id': 106, 'title': 'Shakespeare Analysis', 'url': '/files/shakespeare.pdf', 'type': 'notes', 'subject': 'English'},
      {'id': 107, 'title': 'Python Programming Basics', 'url': '/files/python.mp4', 'type': 'videos', 'subject': 'Computer Science'},
      {'id': 108, 'title': 'Calculus PYQ 2025', 'url': '/files/calculus_pyq.pdf', 'type': 'pyq', 'subject': 'Mathematics'},
      {'id': 109, 'title': 'Thermodynamics PYQ', 'url': '/files/thermo_pyq.pdf', 'type': 'pyq', 'subject': 'Physics'},
      {'id': 110, 'title': 'Periodic Table Guide', 'url': '/files/periodic_table.pdf', 'type': 'textbook', 'subject': 'Chemistry'},
      {'id': 111, 'title': 'Genetics Crash Course', 'url': '/files/genetics.mp4', 'type': 'videos', 'subject': 'Biology'},
      {'id': 112, 'title': 'Data Structures & Algorithms', 'url': '/files/dsa.pdf', 'type': 'textbook', 'subject': 'Computer Science'},
      {'id': 113, 'title': 'Statistics Primer', 'url': '/files/stats.pdf', 'type': 'notes', 'subject': 'Mathematics'},
      {'id': 114, 'title': 'Electromagnetism Notes', 'url': '/files/em_notes.pdf', 'type': 'notes', 'subject': 'Physics'},
    ];
    
    // --- Subjects ---
    if (p == '/subjects') return [
      {'name': 'Mathematics', 'symbol': 'calculator', 'class_name': 'All Classes'},
      {'name': 'Science', 'symbol': 'atom', 'class_name': 'All Classes'},
      {'name': 'History', 'symbol': 'globe', 'class_name': 'All Classes'},
      {'name': 'Literature', 'symbol': 'book', 'class_name': 'All Classes'},
      {'name': 'Computer Science', 'symbol': 'laptop', 'class_name': 'All Classes'},
      {'name': 'General', 'symbol': 'folder', 'class_name': 'All Classes'},
    ];
    
    // --- Teacher endpoints ---
    if (p == '/teacher/me') return {
      'username': 'admin',
      'name': 'Hub Administrator',
      'department': 'System',
      'scholar_id': 'LUMINA_01-ADMIN',
      'reset_required': 0,
    };
    
    if (p == '/teacher/scholars') return [
      {'id': 'LUMINA_01-A1B2C3D4', 'name': 'Alice Johnson', 'reset_required': 0},
      {'id': 'LUMINA_01-E5F6G7H8', 'name': 'Bob Smith', 'reset_required': 1},
      {'id': 'LUMINA_01-I9J0K1L2', 'name': 'Charlie Brown', 'reset_required': 0},
      {'id': 'LUMINA_01-M3N4O5P6', 'name': 'Diana Lee', 'reset_required': 0},
      {'id': 'LUMINA_01-Q7R8S9T0', 'name': 'Ethan Davis', 'reset_required': 1},
      {'id': 'LUMINA_01-U1V2W3X4', 'name': 'Fiona Martinez', 'reset_required': 0},
    ];
    
    if (p == '/teachers') return [
      {'username': 'admin', 'name': 'Administrator', 'department': 'System', 'reset_required': 0},
      {'username': 'sarah.mitchell', 'name': 'Dr. Sarah Mitchell', 'department': 'Science', 'reset_required': 0},
      {'username': 'james.anderson', 'name': 'Prof. James Anderson', 'department': 'Mathematics', 'reset_required': 1},
      {'username': 'emily.clarke', 'name': 'Ms. Emily Clarke', 'department': 'English', 'reset_required': 0},
      {'username': 'robert.chen', 'name': 'Mr. Robert Chen', 'department': 'Computer Science', 'reset_required': 0},
    ];
    
    // --- Token ---
    if (p == '/token') {
      final role = queryParams?['role'] ?? 'admin';
      return {
        'access_token': 'LUMINA_HUB-demotoken',
        'token_type': 'bearer',
        'username': 'admin',
        'name': 'Hub Administrator',
        'department': 'System',
        'scholar_id': 'LUMINA_01-ADMIN',
        'role': role,
        'reset_required': 0,
      };
    }
    
    if (p == '/whoami') return {'username': 'admin', 'role': 'admin'};
    
    // --- Teacher CRUD (return success for any mutation) ---
    if (p == '/teacher/subjects' || p == '/teacher/subjects/delete') return {'status': 'success'};
    if (p.startsWith('/teacher/profiles')) return {'status': 'success'};
    if (p.startsWith('/teacher/change-password')) return {'status': 'success'};
    if (p.startsWith('/teacher/disable-default-admin')) return {'status': 'success'};
    if (p.startsWith('/teacher/upload')) return {'status': 'success'};
    if (p.startsWith('/teacher/upload-zim')) return {'status': 'success', 'imported': ['demo_article_1.html']};
    if (p.startsWith('/teacher/import-server-file')) return {'status': 'success'};
    if (p.startsWith('/teacher/resources/')) return {'status': 'success'};
    
    // Student reset/delete — dynamic paths like /teacher/scholars/reset-password/{id}
    if (p.contains('/scholars/reset-password') || p.contains('/scholars/delete')) return {'status': 'success'};
    if (p.startsWith('/teacher/reset-password/')) return {'status': 'success'};
    
    // --- Stats & System ---
    if (p == '/stats') return {'storage_percent': 45.2, 'battery_percent': 82};
    if (p == '/system/stats') return {'status': 'healthy'};
    if (p == '/system/sync-time') return {'status': 'ok'};
    
    // --- Files ---
    if (p == '/files') return [
      {'name': 'algebra.pdf', 'size': 2450000},
      {'name': 'mechanics.pdf', 'size': 3120000},
      {'name': 'organic_chem.mp4', 'size': 45000000},
      {'name': 'cell_bio.pdf', 'size': 1800000},
      {'name': 'EduMesh.apk', 'size': 65000000},
    ];
    
    // --- Admin ---
    if (p == '/admin/log') {
      final logs = [
        '2026-05-30T08:23:15 - Admin admin created subject "Computer Science"',
        '2026-05-30T08:24:01 - Admin admin uploaded resource "Python Basics" (CS)',
        '2026-05-30T08:25:44 - Admin admin reset password for scholar A1B2C3D4',
        '2026-05-30T08:26:30 - Admin admin deleted resource id=99',
        '2026-05-30T08:27:12 - Admin admin created teacher profile emily.clarke',
        '2026-05-30T08:28:05 - Admin admin imported ZIM (82 pages)',
        '2026-05-30T08:29:33 - Admin admin changed log retention policy to 7d',
        '2026-05-30T08:30:00 - Admin admin downloaded audit logs',
        '2026-05-30T08:31:22 - Admin admin disabled default admin account',
        '2026-05-30T08:32:15 - Admin admin deleted student account SCH-009',
      ];
      return {'log': logs};
    }
    
    if (p == '/api/admin/settings') {
      // POST returns success, GET returns current settings
      return {'log_retention': '30d'};
    }
    
    if (p.startsWith('/api/admin/logs/download')) return 'No demo logs available.';
    
    // --- ZIM ---
    if (p == '/zim/search') return {'results': [
      {'article_id': 'DMO001', 'title': 'Demo Photosynthesis'},
      {'article_id': 'DMO002', 'title': 'Demo Solar System'},
      {'article_id': 'DMO003', 'title': 'Demo Human Anatomy'},
    ]};
    
    if (p == '/zim/page') return {'id': queryParams?['id'] ?? 'DMO001', 'html': '<html><body><h1>Demo ZIM Article</h1><p>This is demo content.</p></body></html>'};
    
    // --- Limits ---
    if (p == '/api/limits') return {'zim_upload_max_size': 5000000000};
    
    // --- Sync (accepting mutations) ---
    if (p.startsWith('/sync/')) return {'status': 'synced'};
    
    // --- Logout, etc. ---
    if (p == '/logout' || p == '/generate_204') return {'status': 'ok'};
    
    // Fallback: unknown path
    return null;
  }
}
