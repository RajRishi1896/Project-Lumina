/* ── Shared Lumina Dashboard JS ────────────────────────────────────────── */

/* ── Helpers ─────────────────────────────────────────────────────────────── */

/**
 * Escape HTML special characters in a string to prevent XSS.
 * Handles &, ", ', <, >, and backtick.
 * @param {*} str - Value to escape (converted to string)
 * @returns {string} Escaped string safe for innerHTML
 */
function esc(str) {
    return String(str).replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/'/g,'&#39;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/`/g,'&#96;');
}

/**
 * Debounce a function call.
 * @param {Function} fn - Function to debounce
 * @param {number} delay - Delay in milliseconds
 * @returns {Function} Debounced function
 */
function debounce(fn, delay) {
    var timer;
    return function() {
        clearTimeout(timer);
        timer = setTimeout(function() { fn.apply(this, arguments); }, delay);
    };
}

/**
 * Focus trap utility for modal dialogs.
 * Traps focus within the given element and restores focus to the trigger element on close.
 * @param {HTMLElement} modal - The modal element to trap focus within
 * @param {HTMLElement} trigger - The element that opened the modal (focus returns here on close)
 * @returns {Object} Object with `activate` and `deactivate` methods
 */
/**
 * Convert an ISO date string to a human-friendly relative time label.
 * @param {string|null} iso - ISO date string or null
 * @returns {string} Relative time string (e.g. "5 minutes ago")
 */
function timeAgo(iso) {
    if (!iso) return __('students.never');
    var diff = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
    if (diff < 60) return __('students.just_now');
    if (diff < 3600) return __('students.minutes_ago', {n: Math.floor(diff / 60)});
    if (diff < 86400) return __('students.hours_ago', {n: Math.floor(diff / 3600)});
    if (diff < 172800) return __('students.yesterday');
    if (diff < 2592000) return __('students.days_ago', {n: Math.floor(diff / 86400)});
    return new Date(iso).toLocaleDateString();
}


/* ── i18n / Language ──────────────────────────────────────────────────────── */

/** @type {Array<{code:string, name:string, native:string}>} Available languages */
const LANGUAGES = [
    { code: 'en', name: 'English', native: 'English' },
    { code: 'hi', name: 'Hindi', native: 'हिन्दी' },
    { code: 'kn', name: 'Kannada', native: 'ಕನ್ನಡ' },
    { code: 'fr', name: 'French', native: 'Français' },
];

/** @type {string} Current language code, persisted to localStorage */
let currentLang = localStorage.getItem('lumina-lang') || 'en';

/**
 * Translation table. Add new strings here with keys, then reference them via __('key') in HTML/JS.
 * Keys follow the pattern: page_element_description (lower_snake_case).
 * External JSON files in /static/lang/{code}.json are loaded and merged over these defaults.
 */
const TRANSLATIONS = {
  en: {
    "courses.page_title": "Lumina Hub | Courses",
    "courses.title": "My Courses",
    "courses.page_description": "Create and manage courses with quizzes and resources.",
    "courses.create": "Create Course",
    "courses.filter_subject": "Subject",
    "courses.filter_grade": "Grade",
    "courses.filter_all": "All",
    "courses.search_label": "Search courses",
    "courses.search_placeholder": "Search by title...",
    "courses.th_title": "Title",
    "courses.th_subject": "Subject",
    "courses.th_grade": "Grade",
    "courses.th_language": "Language",
    "courses.th_status": "Status",
    "courses.th_resources": "Resources",
    "courses.th_actions": "Actions",
    "courses.empty": "No courses created yet. Click \"Create Course\" to get started.",
    "courses.status_published": "Published",
    "courses.status_draft": "Draft",
    "courses.edit": "Edit",
    "courses.delete": "Delete",
    "courses.export_zip": "Export ZIP",
    "courses.back_to_list": "Back to Courses",
    "courses.editor_new": "New Course",
    "courses.editor_edit": "Edit Course",
    "courses.editor_title_label": "Course Title",
    "courses.editor_title_placeholder": "e.g. Algebra Fundamentals",
    "courses.editor_subject_label": "Subject",
    "courses.editor_subject_select": "Select subject...",
    "courses.editor_grade_label": "Grade",
    "courses.editor_language_label": "Language",
    "courses.editor_desc_label": "Description",
    "courses.editor_desc_placeholder": "Brief description of the course...",
    "courses.similar_title": "Similar Courses",
    "courses.similar_desc": "Link similar courses together so students can discover related content.",
    "courses.similar_search_label": "Search courses",
    "courses.similar_search_placeholder": "Type to search courses...",
    "courses.similar_empty": "No linked courses yet.",
    "courses.cover_title": "Cover Image",
    "courses.cover_empty": "No image",
    "courses.cover_remove": "Remove",
    "courses.add_chapter": "Add Chapter",
    "courses.chapter_cancel": "Cancel",
    "courses.chapter_delete_body": "Resources in this chapter will become ungrouped.",
    "courses.chapter_delete_btn": "Delete",
    "courses.chapter_delete_title": "Delete Chapter",
    "courses.chapter_save": "Save",
    "courses.chapter_save_failed": "Failed to save chapter.",
    "courses.chapter_th_chapter": "Chapter",
    "courses.chapter_title_label": "Chapter Title",
    "courses.chapter_title_required": "Chapter title is required.",
    "courses.chapters_empty": "No chapters yet. Add chapters to organize resources.",
    "courses.chapters_title": "Chapters",
    "courses.resources_label": "resources",
    "courses.notif.save_course_first": "Save the course first, then add chapters.",
    "courses.resources_title": "Course Resources",
    "courses.add_resource": "Add Resource",
    "courses.add_quiz": "Add Quiz",
    "courses.resource_th_title": "Title",
    "courses.resource_th_type": "Type",
    "courses.resource_th_size": "Size",
    "courses.resource_th_actions": "Actions",
    "courses.resources_empty": "No resources added yet.",
    "courses.remove": "Remove",
    "courses.save_draft": "Save Draft",
    "courses.publish": "Publish",
    "courses.grade_label": "Grade {grade}",
    "courses.confirm_delete_title": "Delete Course",
    "courses.confirm_delete_body": "Are you sure you want to permanently delete \"{title}\"?",
    "courses.confirm_delete_btn": "Delete",
    "courses.notif.load_failed": "Could not load courses.",
    "courses.import": "Import Course",
    "courses.notif.connection_error": "Connection error.",
    "courses.notif.imported": "Course imported successfully.",
    "courses.notif.import_failed": "Could not import course.",
    "courses.notif.deleted": "Course deleted.",
    "courses.notif.delete_failed": "Could not delete course.",
    "courses.notif.saved": "Course saved successfully.",
    "courses.notif.save_failed": "Could not save course.",
    "courses.notif.title_required": "Please enter a course title.",
    "courses.notif.question_text_required": "Please enter the question text.",
    "courses.notif.answer_required": "Please enter the correct answer.",
    "courses.notif.options_required": "Please add at least 2 options.",
    "courses.notif.correct_required": "Please select the correct answer.",
    "courses.notif.quiz_title_required": "Please enter a quiz title.",
    "courses.notif.quiz_questions_required": "Please add at least one question.",
    "courses.notif.save_course_first": "Please save the course first before adding a quiz.",
    "courses.notif.quiz_saved": "Quiz saved successfully.",
    "courses.notif.quiz_save_failed": "Could not save quiz.",
    "courses.quiz_builder": "Quiz Builder",
    "courses.quiz_title_label": "Quiz Title",
    "courses.quiz_title_placeholder": "e.g. Chapter 1 Quiz",
    "courses.quiz_time_label": "Time Limit (minutes)",
    "courses.quiz_threshold_label": "Pass Threshold (%)",
    "courses.quiz_attempts_label": "Max Attempts",
    "courses.quiz_shuffle_label": "Shuffle questions",
    "courses.quiz_custom": "Custom",
    "courses.quiz_questions_title": "Questions",
    "courses.quiz_add_question": "Add Question",
    "courses.quiz_questions_empty": "No questions added yet.",
    "courses.quiz_edit_question": "Edit Question",
    "courses.quiz_new_question": "New Question",
    "courses.quiz_q_type_label": "Question Type",
    "courses.quiz_q_type_mcq": "MCQ (Single)",
    "courses.quiz_q_type_tf": "True / False",
    "courses.quiz_q_type_fill": "Fill in the Blanks",
    "courses.quiz_q_type_multi": "Multi-Select",
    "courses.quiz_q_image_label": "Question Image (optional)",
    "courses.quiz_q_text_label": "Question Text",
    "courses.quiz_q_text_placeholder": "Enter the question...",
    "courses.quiz_q_options_label": "Options",
    "courses.quiz_add_option": "+ Add Option",
    "courses.quiz_q_fill_label": "Correct Answer",
    "courses.quiz_q_fill_placeholder": "Enter the correct answer...",
    "courses.quiz_q_explanation_label": "Explanation (optional)",
    "courses.quiz_q_explanation_placeholder": "Explain why this answer is correct...",
    "courses.quiz_cancel": "Cancel",
    "courses.quiz_save_question": "Save Question",
    "courses.quiz_preview": "Preview",
    "courses.quiz_save": "Save Quiz",
    "courses.quiz_untitled": "Untitled Quiz",
    "courses.preview_meta": "{count} questions | {time} min | pass: {threshold}%",
    "courses.preview_question_num": "Q{n}",
    "courses.preview_fill_input": "[Fill in the blank]",
    "courses.preview_explanation": "Explanation",
    "content.general_subject": "General",
    "content.all_subjects": "All Subjects",
    "content.no_other_subjects": "No other subjects available",
    "content.notif.subject_name_required": "Please enter a subject name.",
    "content.notif.subject_created": "Subject \"{name} ({class_name})\" created successfully.",
    "content.notif.subject_create_failed": "Could not create subject.",
    "content.notif.connection_error": "Error connecting to server.",
    "content.notif.title_required": "Please enter a title and select a file.",
    "content.notif.upload_ok": "Resource uploaded successfully.",
    "content.notif.upload_failed": "Upload failed.",
    "content.notif.delete_title": "Delete Resource",
    "content.notif.delete_confirm": "Are you sure you want to permanently delete the resource \"{title}\"?",
    "content.notif.delete_ok": "Resource \"{title}\" deleted.",
    "content.notif.delete_failed": "Could not delete resource.",
    "content.notif.network_error": "Network error.",
    "content.notif.transfer_target_required": "Please select a target subject to transfer files to.",
    "content.topics_title": "Manage Topics",
    "content.topics_th_subject": "Subject",
    "content.topics_th_name": "Topic Name",
    "content.topics_th_action": "Action",
    "content.topics_empty": "No topics created yet.",
    "content.topics_modal_title": "Add New Topic",
    "content.topics_delete_title": "Delete Topic",
    "content.topics_delete_confirm": "Delete \"{name}\"? Resources will be moved to General unless transferred.",
    "content.topics_deleted_with_resources": "Topic \"{name}\" and {count} resource(s) deleted.",
    "content.topic_transfer.select_topic": "Select a topic to transfer resources to",
    "content.notif.subject_deleted": "Subject \"{name}\" deleted successfully.",
    "content.notif.subject_delete_failed": "Could not delete subject.",
    "content.notif.pwd_fields_required": "Please fill in both fields.",
    "content.notif.pwd_mismatch": "Passwords do not match.",
    "content.notif.pwd_updated": "Password updated successfully. Reloading...",
    "content.notif.pwd_update_failed": "Could not update password.",
    "content.library_th_downloads": "Downloads",
    "content.library_th_topic": "Topic",
    "content.upload_label_topic": "Chapter / Topic",
    "content.upload_option_general_topic": "General (No Topic)",
    "danger.manage_subjects": "Manage Subjects",
    "app.tagline": "Your Offline Learning Network",
    "app.title": "Lumina Hub",
    "content.add_subject_button": "Add Subject",
    "content.add_subject_label_class": "Class/Grade",
    "content.add_subject_label_name": "Subject Name",
    "content.add_subject_label_symbol": "Symbol",
    "content.add_subject_placeholder_class": "All Classes",
    "content.add_subject_placeholder_name": "e.g. Physics",
    "content.add_subject_symbol_calculator": "Calculator",
    "content.add_subject_symbol_placeholder": "Select a symbol...",
    "content.add_subject_title": "Add New Subject",
    "content.confirm_delete_btn": "Delete",
    "content.confirm_ok_btn": "Confirm",
    "content.delete": "Delete",
    "content.grade": "Grade",
    "content.library_empty": "No resources found.",
    "content.library_filter_all_subjects": "All Subjects",
    "content.library_filter_subject_label": "Filter Subject:",
    "content.library_search_label": "Search resources",
    "content.library_search_placeholder": "Search resources...",
    "content.library_th_action": "Action",
    "content.library_th_subject": "Subject",
    "content.library_th_title": "Title",
    "content.library_th_type": "Type",
    "content.library_title": "Mesh Library",
    "content.manage_subjects_empty": "No subjects found.",
    "content.manage_subjects_search_label": "Search subjects",
    "content.manage_subjects_search_placeholder": "Search by subject name...",
    "content.manage_subjects_th_action": "Action",
    "content.manage_subjects_th_class": "Class/Grade",
    "content.manage_subjects_th_icon": "Icon",
    "content.manage_subjects_th_name": "Subject Name",
    "content.manage_subjects_title": "Manage Subjects & Syllabus",
    "content.modal_cancel": "Cancel",
    "content.modal_confirm": "Confirm",
    "content.modal_confirm_action_text": "Are you sure you want to proceed?",
    "content.modal_confirm_action_title": "Confirm Action",
    "content.modal_confirm_deletion": "Delete Subject",
    "content.modal_confirm_password_label": "Confirm New Password",
    "content.modal_confirm_password_placeholder": "Confirm new password",
    "content.modal_delete_permanently": "Delete Permanently",
    "content.modal_delete_permanently_desc": "All resource files will be permanently deleted.",
    "content.modal_delete_subject_title": "Delete Subject",
    "content.modal_new_password_label": "New Password",
    "content.modal_new_password_placeholder": "Enter new password",
    "content.modal_password_requirement": "Must be 8+ chars, with uppercase, lowercase & a digit.",
    "content.modal_password_reset_desc": "An administrator has forced a password reset on your account. Please set a new password to continue.",
    "content.modal_password_reset_title": "Password Reset Required",
    "content.modal_resource_file_action": "What should happen to resource files?",
    "content.modal_transfer_resources": "Transfer to Another Subject",
    "content.modal_transfer_resources_desc": "Resource files will be moved to the selected subject.",
    "content.modal_transfer_to_subject": "Transfer to Subject",
    "content.modal_update_continue": "Update and Continue",
    "content.page_description": "Upload and manage educational resources.",
    "content.page_title": "Content Manager",
    "content.subject": "Subject",
    "content.subtitle": "Upload and manage educational resources.",
    "content.title": "Content Manager",
    "content.upload": "Upload",
    "content.upload_button": "Upload",
    "content.upload_label_category": "Category",
    "content.upload_label_file": "File",
    "content.upload_label_subject": "Subject",
    "content.upload_label_title": "Title",
    "content.upload_option_general": "General",
    "content.upload_option_zim": "ZIM Archive",
    "content.upload_option_notes": "Notes",
    "content.upload_option_pyq": "PYQ",
    "content.upload_option_textbook": "Textbook",
    "content.upload_option_video": "Video",
    "content.upload_placeholder_title": "Enter resource title",
    "content.upload_title": "Upload Resource",
    "danger.alert.admin_disabled": "Default admin login disabled successfully.",
    "danger.alert.admin_disabled_failed": "Could not disable default admin.",
    "danger.alert.connection_error": "Error connecting to server.",
    "danger.alert.delete_profile_failed": "Could not delete profile.",
    "danger.page_title": "Lumina Hub | Danger Zone",
    "danger.cancel": "Cancel",
    "danger.confirm": "Confirm",
    "danger.confirm.delete_btn": "Delete",
    "danger.confirm.delete_admin": "Are you sure you want to delete admin profile \"{username}\"?",
    "danger.confirm.delete_admin_title": "Delete Admin Profile",
    "danger.confirm.delete_subject_title": "Delete Subject",
    "danger.confirm.delete_subject": "Delete \"{name}\"? Resources using this subject will not be affected.",
    "danger.confirm.delete_subject_btn": "Delete",
    "danger.confirm.delete_student": "Are you sure you want to permanently delete student \"{name}\"? This will wipe all download history and sync records.",
    "danger.confirm.delete_student_title": "Delete Student Account",
    "danger.confirm.delete_teacher": "Are you sure you want to delete teacher profile \"{username}\"?",
    "danger.confirm.delete_teacher_title": "Delete Teacher Profile",
    "danger.confirm.disable_admin": "Are you sure you want to disable the default admin login ('admin')? Make sure you have your teacher credentials saved! (To reset later, run ./reset_admin.sh)",
    "danger.confirm.disable_admin_title": "Disable Default Admin",
    "danger.confirm.force_reset_admin": "Are you sure you want to force password reset on admin \"{username}\"?",
    "danger.confirm.force_reset_student": "Are you sure you want to force password reset on student \"{name}\"? They will be forced to change their password to continue using the mobile application.",
    "danger.confirm.force_reset_teacher": "Are you sure you want to force password reset on teacher \"{username}\"?",
    "danger.confirm.force_reset_title": "Force Password Reset",
    "danger.confirm.ok_btn": "Confirm",
    "danger.confirm_text": "Are you sure you want to proceed?",
    "danger.confirm_title": "Confirm Action",
    "danger.create": "Create",
    "danger.create_account_title": "Create Account",
    "danger.create_admin": "+ Create Admin",
    "danger.create_student": "+ Create Student",
    "danger.create_teacher": "+ Create Teacher",
    "danger.default_account": "Default account",
    "danger.delete": "Delete",
    "danger.disable_default_admin": "Disable Default Admin Login (admin)",
    "danger.error.subject_name_required": "Subject name is required.",
    "danger.error.both_fields": "Please fill in both fields.",
    "danger.error.connection": "Error connecting to server.",
    "danger.error.create_admin_failed": "Could not create admin account.",
    "danger.error.create_student_failed": "Could not create student.",
    "danger.error.create_teacher_failed": "Could not create teacher account.",
    "danger.error.name_username_required": "Please fill in name and username.",
    "danger.error.passwords_match": "Passwords do not match.",
    "danger.error.required_fields": "Please fill in all required fields.",
    "danger.error.update_failed": "Could not update password.",
    "danger.empty_admins": "No admin accounts registered yet.",
    "danger.empty_students": "No student accounts registered yet.",
    "danger.empty_teachers": "No teacher accounts registered yet.",
    "danger.force_reset_confirm_pwd_label": "Confirm New Password",
    "danger.force_reset_confirm_pwd_placeholder": "Confirm new password",
    "danger.force_reset_desc": "An administrator has forced a password reset on your account.",
    "danger.force_reset_new_pwd_label": "New Password",
    "danger.force_reset_new_pwd_placeholder": "Enter new password",
    "danger.force_reset_pwd": "Force Reset Pwd",
    "danger.force_reset_title": "Password Reset Required",
    "danger.manage_admins": "Manage Admin Accounts",
    "danger.manage_admins_desc": "Manage admin accounts for the hub.",
    "danger.manage_students": "Manage Student Accounts",
    "danger.manage_teachers": "Manage Teacher Accounts",
    "danger.modal.create_admin_title": "Create Admin Account",
    "danger.modal.create_student_title": "Create Student Account",
    "danger.modal.create_teacher_title": "Create Teacher Account",
    "danger.modal_department": "Department",
    "danger.modal_department_placeholder": "e.g. Science",
    "danger.modal_full_name": "Full Name",
    "danger.modal_full_name_placeholder": "e.g. John Smith",
    "danger.modal_grade_class": "Grade/Class",
    "danger.modal_grade_class_placeholder": "e.g. Grade 10",
    "danger.modal_password": "Password",
    "danger.modal_password_placeholder": "Enter password",
    "danger.modal_username": "Username",
    "danger.modal_username_placeholder": "e.g. jsmith",
    "danger.no_matching_admins": "No matching admin accounts found.",
    "danger.no_matching_students": "No matching students found.",
    "danger.no_matching_teachers": "No matching teachers found.",
    "danger.notif.admin_created": "Admin account \"{username}\" created successfully.",
    "danger.notif.admin_pwd_reset": "Admin \"{username}\" password reset to default.",
    "danger.notif.admin_pwd_reset_failed": "Could not reset admin password.",
    "danger.notif.delete_failed": "Could not delete account.",
    "danger.notif.network_error": "Network error.",
    "danger.notif.subject_add_failed": "Failed to add subject.",
    "danger.notif.subject_deleted": "Subject deleted.",
    "danger.notif.subject_delete_failed": "Failed to delete.",
    "danger.notif.student_created": "Student \"{name}\" created successfully.",
    "danger.notif.student_deleted": "Student \"{name}\" deleted.",
    "danger.notif.student_pwd_reset": "Password for student \"{name}\" reset to default.",
    "danger.notif.student_pwd_reset_failed": "Could not reset student password.",
    "danger.notif.teacher_pwd_reset": "Teacher \"{username}\" password reset to default.",
    "danger.notif.teacher_pwd_reset_failed": "Could not reset teacher password.",
    "danger.password_hint": "Must be 8+ chars, with uppercase, lowercase & a digit.",
    "danger.search_admins_label": "Search admins",
    "danger.search_admins_placeholder": "Search by username, name or department...",
    "danger.search_students_label": "Search students",
    "danger.search_students_placeholder": "Search by student name or scholar ID...",
    "danger.search_teachers_label": "Search teachers",
    "danger.search_teachers_placeholder": "Search by username, full name or department...",
    "danger.status_active": "Active",
    "danger.status_reset_pending": "Reset Pending",
    "danger.subtitle": "Perform critical hub administration cleanup, force resets, and content pruning.",
    "danger.success.password_changed": "Password updated successfully. Reloading...",
    "danger.table_action": "Action",
    "danger.table_department": "Department",
    "danger.table_full_name": "Full Name",
    "danger.table_scholar_id": "Scholar ID",
    "danger.table_status": "Status",
    "danger.table_student_name": "Student Name",
    "danger.table_username": "Username",
    "danger.title": "Danger Zone",
    "danger.update_and_continue": "Update and Continue",
    "danger.manage_grades": "Manage Grades",
    "danger.grade_name_label": "Grade Name",
    "danger.add_grade_btn": "+ Add Grade",
    "danger.table_grade_name": "Grade Name",
    "danger.empty_grades": "No grades created yet.",
    "danger.confirm.delete_grade_title": "Delete Grade",
    "danger.confirm.delete_grade": "Delete grade \"{name}\"? Resources assigned to this grade will be permanently removed.",
    "danger.notif.grade_created": "Grade \"{name}\" created successfully.",
    "danger.notif.grade_deleted": "Grade \"{name}\" deleted.",
    "danger.error.grade_name_required": "Please enter a grade name.",
    "danger.error.grade_create_failed": "Could not create grade. It may already exist.",
    "danger.error.grade_delete_failed": "Could not delete grade.",
    "danger.transfer.select_grade": "Select a grade to transfer resources to",
    "danger.transfer.select_subject": "Select a subject to transfer resources to",
    "danger.transfer.transfer_and_delete": "Transfer then Delete",
    "danger.transfer.select_target": "Please select a target to transfer resources to",
    "danger.transfer.done": "Resources transferred from \"{name}\" to \"{target}\".",
    "danger.transfer.done_subject": "Resources transferred from \"{name}\" to \"{target}\".",
    "error.page_title": "Access Error - Lumina Hub",
    "error_access_denied_badge": "Access Denied",
    "error_access_denied_message": "This page requires teacher or administrator privileges. Please log in with an authorized account.",
    "error_access_denied_title": "You don’t have access",
    "error_back_home": "Back to Home",
    "error_not_found_badge": "Not Found",
    "error_not_found_message": "The page you’re looking for doesn’t exist or has been moved.",
    "error_not_found_title": "Page Not Found",
    "error_session_expired_badge": "Session Expired",
    "error_session_expired_message": "Your session has expired or you are not logged in. Please log in again to continue.",
    "error_session_expired_title": "Session Expired",
    "help.admin": "Admin Tasks",
    "help.admin_body": "<ul><li><strong>Danger Zone</strong> &mdash; Reset all data, force admin password reset, set log retention, and view audit logs.</li><li><strong>Settings</strong> &mdash; Toggle dark mode, view system info (Python version, database path, hostname).</li><li><strong>Setup script</strong> &mdash; Run <code>sudo ./setup_hub.sh</code> to provision the hotspot, install dependencies, and configure the systemd service from scratch.</li></ul>",
    "help.getting_started": "Getting Started",
    "help.getting_started_body": "<ul><li><strong>Connect</strong> &mdash; Join the <strong>EduMesh</strong> Wi-Fi hotspot broadcast by the Hub laptop. The captive portal opens automatically.</li><li><strong>Install the app</strong> &mdash; On the welcome page, download the EduMesh APK and install it on your Android phone. Enable \"Install from Unknown Sources\" if prompted.</li><li><strong>Register</strong> &mdash; Open the app, enter your name, and you are in. The Hub assigns you a permanent student ID.</li><li><strong>Start learning</strong> &mdash; Browse textbooks, videos, and other resources. Download them to use offline.</li></ul>",
    "help.page_title": "Lumina Hub | Help & Documentation",
    "help.subtitle": "How to use the Lumina Hub and EduMesh app.",
    "help.teachers": "For Teachers",
    "help.teachers_body": "<ul><li><strong>Upload resources</strong> &mdash; Go to Content Manager, select a PDF or video, give it a title and subject, and click Upload. Resources are available to all students immediately.</li><li><strong>Manage content</strong> &mdash; Filter by subject and grade to find resources. Click delete to remove any resource and its file.</li><li><strong>View students</strong> &mdash; Go to Students to see all registered students, filter by grade, or search by name. Each card shows weekly study time, streak, and saved resources.</li><li><strong>Detailed analytics</strong> &mdash; Click a student to see their full profile with study time breakdown and resource count.</li><li><strong>Change your password</strong> &mdash; Go to Account Settings to update your login credentials, display name, and department.</li></ul>",
    "help.title": "Help & Instructions",
    "help.tracking": "Student Tracking",
    "help.tracking_body": "<ul><li><strong>Study time</strong> &mdash; The app tracks focused study sessions using the built-in timer. Total weekly minutes are synced to the Hub.</li><li><strong>Streak</strong> &mdash; Consecutive days the student uses the app. Calculated on the phone and synced to the Hub.</li><li><strong>Saved resources</strong> &mdash; Each time a student bookmarks or downloads a resource, the count is updated.</li><li><strong>Privacy</strong> &mdash; Individual events (which PDF was opened, what was searched) stay on the student&#39;s phone and are never sent to the Hub.</li></ul>",
    "help.troubleshooting": "Troubleshooting",
    "help.troubleshooting_body": "<ul><li><strong>App cannot connect</strong> &mdash; Ensure your phone is on the EduMesh Wi-Fi and the Hub laptop is powered on. Restart the app and wait a few seconds.</li><li><strong>Forgot your password</strong> &mdash; Plug a keyboard into the Hub laptop and run <code>sudo ./reset_admin.sh</code> in a terminal. This resets the admin password to <code>lumina2026</code>.</li><li><strong>App is slow</strong> &mdash; Close other apps, restart EduMesh, or clear app data from Android Settings and reinstall.</li><li><strong>Hub storage is full</strong> &mdash; Delete unused resources from Content Manager. Check disk usage on the <span data-i18n=\"sidebar.home\">Home</span> page. For advanced cleanup, run <code>sudo ./setup_hub.sh</code>.</li></ul>",
    "index.page_title": "Lumina Hub | Dashboard",
    "index.server_version": "Lumina Hub v1.0",
    "index.unit_hours_short": "h",
    "index.unit_minutes_short": "m",
    "index.unit_seconds_short": "s",
    "index.unit_gb": "GB",
    "index.unit_percent": "%",
    "index_info_disk": "Disk Usage",
    "index_info_host": "Host",
    "index_info_server": "Server",
    "index_info_uptime": "Uptime",
    "index_stat_battery": "Battery",
    "index_stat_resources": "Resources",
    "index_stat_storage": "Storage",
    "index_stat_subjects": "Subjects",
    "index_stat_uptime": "Uptime",
    "index_system_info": "System Information",
    "index_welcome_back": "Welcome back. Your local education server is running.",
    "log.changed_retention": "changed log retention policy to {policy}",
    "log.created_admin": "created admin account '{username}'",
    "log.created_student": "created student account '{username}'",
    "log.created_teacher": "created teacher account '{username}'",
    "log.disabled_default_admin": "disabled the default admin account",
    "log.enabled_default_admin": "enabled the default admin account",
    "log.hard_deleted": "hard-deleted resource id={id} '{title}'",
    "log.reset_teacher_password": "reset password for teacher {username}",
    "log.soft_deprecated": "soft-deprecated resource id={id} '{title}' ({count} active downloads)",
    "nav.download": "Download App",
    "nav.help": "Help",
    "nav.language": "Select Language",
    "nav.theme": "Toggle Dark Mode",
    "security.account_settings": "Account Settings",
    "security.aria.hide_password": "Hide password",
    "security.aria.show_password": "Show password",
    "security.cancel": "Cancel",
    "security.change_password_title2": "Change Admin Password",
    "security.confirm": "Confirm",
    "security.confirm.delete": "Delete",
    "security.confirm.ok": "Confirm",
    "security.confirm_action": "Confirm Action",
    "security.confirm_new_password": "Confirm New Password",
    "security.confirm_new_password_placeholder": "Confirm new password",
    "security.confirm_proceed": "Are you sure you want to proceed?",
    "security.error.both_fields": "Please fill in both fields.",
    "security.error.connection": "Error connecting to server.",
    "security.error.connection_error": "Connection error.",
    "security.error.current_password": "Error: check your current password.",
    "security.error.dept_empty": "Department cannot be empty.",
    "security.error.digit": "Password must contain at least one digit.",
    "security.error.lowercase": "Password must contain at least one lowercase letter.",
    "security.error.name_empty": "Name cannot be empty.",
    "security.error.password_length": "Password must be at least 8 characters long.",
    "security.error.passwords_match": "Passwords do not match.",
    "security.error.update_dept": "Could not update department.",
    "security.error.update_failed": "Could not update password.",
    "security.error.update_name": "Could not update name.",
    "security.error.uppercase": "Password must contain at least one uppercase letter.",
    "security.page_description": "Update your password, display name, and department.",
    "security.page_title": "Lumina Hub | Account",
    "security.password_reset_description": "An administrator has forced a password reset on your account. Please set a new password to continue.",
    "security.password_reset_required": "Password Reset Required",
    "security.success.force_password_changed": "Password updated successfully. Reloading...",
    "security.success.password_updated": "Password updated.",
    "security.success.profile_updated": "Profile updated successfully.",
    "security.update_and_continue": "Update and Continue",
    "security_change_password_title": "Change Admin Password",
    "security_current_password": "Current Password",
    "security_current_password_placeholder": "Enter current password",
    "security_department": "Department",
    "security_department_placeholder": "Enter your department",
    "security_my_profile": "My Profile",
    "security_name": "Name",
    "security_name_placeholder": "Enter your display name",
    "security_new_password": "New Password",
    "security_new_password_placeholder": "Enter new password",
    "security_password_requirements": "Must be 8+ chars, with uppercase, lowercase &amp; a digit.",
    "security_save": "Save",
    "security_show_password": "Show Password",
    "security_update_password": "Update Password",
    "settings.account_overview": "Account Overview",
    "settings.action": "Action",
    "settings.admin_log": "Live Admin Audit Log",
    "settings.admin_log_desc": "Showing admin actions with pagination. Auto-prunes based on retention policy above.",
    "settings.confirm.body": "Are you sure you want to proceed?",
    "settings.confirm.cancel_btn": "Cancel",
    "settings.confirm.delete_btn": "Delete",
    "settings.confirm.ok_btn": "Confirm",
    "settings.confirm.title": "Confirm Action",
    "settings.connection_error": "Connection error.",
    "settings.download_24h": "Last 24 Hours",
    "settings.download_30d": "Last 30 Days",
    "settings.download_7d": "Last 7 Days",
    "settings.download_all": "All Logs",
    "settings.download_logs": "Download Audit Logs",
    "settings.download_logs_btn": "Download Logs (.txt)",
    "settings.error.both_fields": "Please fill in both fields.",
    "settings.error.connection": "Connection error.",
    "settings.error.load_logs": "Failed to load logs.",
    "settings.error.logs_connection": "Connection error loading logs.",
    "settings.error.passwords_match": "Passwords do not match.",
    "settings.error.retention_update_failed": "Could not update policy.",
    "settings.error.update_failed": "Could not update password.",
    "settings.loading": "Loading...",
    "settings.loading_logs": "Loading logs...",
    "settings.log_retention": "Log Retention Policy",
    "settings.modal.confirm_password_label": "Confirm New Password",
    "settings.modal.confirm_password_placeholder": "Confirm new password",
    "settings.modal.new_password_label": "New Password",
    "settings.modal.new_password_placeholder": "Enter new password",
    "settings.modal.password_hint": "Must be 8+ chars, with uppercase, lowercase & a digit.",
    "settings.modal.reset_body": "An administrator has forced a password reset on your account. You must change your password before you can proceed.",
    "settings.modal.reset_title": "Password Reset Required",
    "settings.modal.update_btn": "Update and Continue",
    "settings.next": "Next",
    "settings.no_admin_actions": "No admin actions recorded yet.",
    "settings.page_of": "Page {current} of {total}",
    "settings.page_title": "Lumina Hub | Settings & System Setup",
    "settings.per_page": "Per page:",
    "settings.previous": "Previous",
    "settings.refresh": "Refresh",
    "settings.retention_24h": "24 Hours",
    "settings.retention_30d": "30 Days (Default)",
    "settings.retention_3m": "3 Months",
    "settings.retention_6m": "6 Months",
    "settings.retention_7d": "7 Days",
    "settings.retention_desc": "Configures how long admin audit logs are stored on the hub server. Pruning is completed automatically with low overhead.",
    "settings.retention_disabled": "Don't Take Logs (Disabled)",
    "settings.retention_duration": "Retention Duration",
    "settings.retention_never": "Never Delete",
    "settings.role_label": "Role:",
    "settings.search_logs_placeholder": "Search logs...",
    "settings.select_duration": "Select Duration to Download",
    "settings.subtitle": "Manage system preferences and configure log retention policies.",
    "settings.success.password_changed": "Password updated successfully. Reloading...",
    "settings.success.retention_updated": "Retention policy successfully updated to \"{policy}\".",
    "settings.timestamp": "Timestamp",
    "settings.title": "Settings & System Setup",
    "settings.confirm.disable_admin_title": "Disable Default Admin",
    "settings.confirm.disable_admin_body": "The default admin account (username: admin) will be blocked from login. You must have at least one other admin or teacher account to do this. Continue?",
    "settings.confirm.disable_admin_btn": "Disable",
    "settings.confirm.enable_admin_title": "Re-enable Default Admin",
    "settings.confirm.enable_admin_body": "Reset the default admin password to lumina2026. Continue?",
    "settings.confirm.enable_admin_btn": "Re-enable",
    "settings.notif.admin_disabled": "Default admin account has been disabled.",
    "settings.notif.disable_failed": "Failed to disable default admin.",
    "settings.notif.admin_enabled": "Default admin account re-enabled. Password reset to lumina2026.",
    "settings.notif.enable_failed": "Failed to re-enable.",
    "settings.username_label": "Username:",
    "settings_language_description": "Choose your preferred language for the dashboard.",
    "settings_language_title": "Language",
    "sidebar.lang_search_placeholder": "Search languages...",
    "sidebar.light_mode": "Light Mode",
    "sidebar.courses": "Courses",
    "sidebar.content": "Content Manager",
    "sidebar.danger": "Danger Zone",
    "sidebar.dark_mode": "Dark Mode",
    "sidebar.help": "Teacher Guide",
    "sidebar.home": "Home",
    "sidebar.logout": "Log out",
    "sidebar.security": "Account",
    "sidebar.settings": "Settings",
    "sidebar.students": "Students",
    "sidebar.toggle_menu": "Toggle Menu",
    "student_detail.active_days": "Active Days",
    "student_detail.day_streak_label": "Day Streak",
    "student_detail.days": "days",
    "student_detail.downloaded_label": "Downloaded",
    "student_detail.hours": "h",
    "student_detail.minutes_abbr": "m",
    "student_detail.page_title": "Student Detail - Lumina Hub",
    "student_detail.resources_saved": "Resources Saved",
    "student_detail.study_time": "Study Time",
    "student_detail.time_this_week_label": "Time This Week",
    "student_detail_back": "Back to",
    "student_detail_day_streak": "Day Streak",
    "student_detail_downloaded": "Downloaded",
    "student_detail_failed": "Failed to load student data.",
    "student_detail_last_updated": "Last updated",
    "student_detail_loading": "Loading student data…",
    "student_detail_no_id": "No student ID provided.",
    "student_detail_no_subject_data": "No subject data available.",
    "student_detail_subject_breakdown": "Subject Breakdown",
    "student_detail_this_week": "(This Week)",
    "student_detail_time_this_week": "Time This Week",
    "student_unknown": "Student",
    "students.all_grades": "All Grades",
    "students.days_ago": "{n}d ago",
    "students.filter_grade": "Filter by grade",
    "students.filter_at_risk": "At-risk filter",
    "students.hours_ago": "{n}h ago",
    "students.just_now": "Just now",
    "students.minutes_ago": "{n}m ago",
    "students.never": "Never",
    "students.search": "Search by name or ID…",
    "students.sort_grade": "Grade",
    "students.sort_label": "Sort by",
    "students.sort_name_asc": "Name (A-Z)",
    "students.sort_name_desc": "Name (Z-A)",
    "students.sort_oldest": "Last Active (Oldest)",
    "students.sort_recent": "Last Active (Recent)",
    "students.sort_study_high": "Study Time (High)",
    "students.sort_study_low": "Study Time (Low)",
    "students.subtitle": "View and manage registered students.",
    "students.title": "Students",
    "students.yesterday": "Yesterday",
    "students.page_title": "Students - Lumina Hub",
    "students_connection_error": "Connection error. Check that the hub server is running.",
    "students_days_abbr": "d",
    "students_saved_abbr": "saved",
    "students_failed_load": "Failed to load students.",
    "students_hours_abbr": "h",
    "students_minutes_abbr": "m",
    "students_last_updated": "Last updated",
    "students_loading": "Loading students…",
    "students_none_registered": "No students registered yet. Students will appear here once they register through the app.",
    "students_refresh": "Refresh",
    "students_filters": "Filters",
    "students_search_label": "Search",
    "students_unknown": "Unknown",
    "students_ungraded": "Ungraded",
    "teacher.help.body": "View setup guides, troubleshooting tips, and admin instructions.",
    "teacher.help.header": "Need help?",
    "teacher.help.link": "Teacher Guide",
    "time_days_ago": "{n}d ago",
    "time_hours_ago": "{n}h ago",
    "time_just_now": "Just now",
    "time_minutes_ago": "{n}m ago",
    "time_seconds_ago": "{n}s ago",
    "time_yesterday": "Yesterday",
    "welcome.battery": "Battery",
    "welcome.battery.percent": "{percent}%",
    "welcome.page_title": "Lumina Hub | Welcome",
    "welcome.show_password": "Show Password",
    "welcome.hide_password": "Hide Password",
    "welcome.display_name_error": "Please enter a name or skip.",
    "welcome.lang_search_placeholder": "Search...",
    "welcome.storage.used_pct": "{pct}% used",
    "welcome.battery_unknown": "Unknown",
    "welcome.connection_error": "Connection error. Please check your network connection.",
    "welcome.display_name_placeholder": "Your display name",
    "welcome.display_name_prompt": "Please enter your display name to personalize your experience.",
    "welcome.display_name_save": "Save",
    "welcome.display_name_skip": "Skip",
    "welcome.display_name_title": "Set Your Display Name",
    "welcome.download_offline": "Downloading for Offline",
    "welcome.enter_both": "Please enter both username and password.",
    "welcome.for_teachers": "For Teachers",
    "welcome.getting_started": "Getting Started",
    "welcome.guide.download_offline_body": "Tap the download icon on any resource to save it to your phone. Downloaded resources work <strong>even when you’re not connected</strong> to the EduMesh network. Perfect for studying anywhere.",
    "welcome.guide.for_teachers_body": "Teachers can log in above using their credentials. Once logged in, you can <strong>upload resources</strong>, <strong>view student analytics</strong>, <strong>manage grades and subjects</strong>, and <strong>configure the hub</strong> -- including changing passwords and managing storage. Visit the <strong>Teacher Guide</strong> in the sidebar after logging in for detailed instructions.",
    "welcome.guide.getting_started_body": "<li><strong>Connect to Wi-Fi</strong> -- Turn on your phone’s Wi-Fi and join the network named <strong>EduMesh</strong>. No password needed.</li><li><strong>Open the welcome page</strong> -- Once connected, a login screen should appear automatically (captive portal). If not, open your browser and go to <strong>http://lumina.hub:8000</strong>.</li><li><strong>Download the app</strong> -- Tap the <strong>Download App</strong> button in the top-right corner of this page to get the EduMesh APK.</li><li><strong>Install the app</strong> -- Open the downloaded file and tap Install. If your phone asks, allow “Install from Unknown Sources” in Settings.</li><li><strong>Register</strong> -- Open the EduMesh app, enter your name, and you’re in. You’ll be assigned a permanent student ID.</li><li><strong>Start learning</strong> -- Browse textbooks, videos, past papers, and more. Tap any resource to view it, or download it to access offline.</li>",
    "welcome.guide.tracking_privacy_body": "<p style=\"font-size:0.875rem;color:var(--text-secondary);line-height:1.7;\">The app tracks your <strong>study time</strong> using a built-in timer and counts your <strong>daily streak</strong> of consecutive study days. This helps teachers see how the class is engaging with materials.</p><p style=\"font-size:0.875rem;color:var(--text-secondary);line-height:1.7;margin-top:0.5rem;\"><strong>Your privacy matters.</strong> Individual details -- like which PDF you opened or what you searched for -- stay on your phone and are <strong>never sent</strong> to the Hub. Only your total weekly minutes, streak days, and resource count are shared.</p>",
    "welcome.guide.troubleshooting_body": "<li><strong>Can’t connect to Wi-Fi?</strong> Make sure the Hub laptop is powered on and broadcasting. Ask your teacher to check.</li><li><strong>Captive portal not opening?</strong> Open your browser and manually go to <strong>http://lumina.hub:8000</strong>.</li><li><strong>App won’t install?</strong> Go to Settings > Security and enable “Install from Unknown Sources”. Then try again.</li><li><strong>App is slow or crashing?</strong> Close other apps, restart EduMesh, or clear app data from Android Settings and reinstall.</li>",
    "welcome.guide.using_app_body": "<p style=\"font-size:0.875rem;color:var(--text-secondary);line-height:1.7;margin-bottom:0.75rem;\">The EduMesh app has four tabs at the bottom:</p><ul style=\"font-size:0.875rem;color:var(--text-secondary);line-height:1.7;padding-left:1.25rem;\"><li><strong>Dashboard</strong> -- See your study stats, recent activity, and quick-access resources.</li><li><strong>Browse</strong> -- Explore all available resources by subject or grade. Search by keyword.</li><li><strong>Saved</strong> -- View resources you’ve bookmarked or downloaded for offline use.</li><li><strong>Profile</strong> -- View your weekly study time, streak, and saved resource count.</li></ul>",
    "welcome.hero.subtitle": "Access textbooks, videos, and study materials from the local mesh -- no internet required.",
    "welcome.hero.title": "Your Offline Learning Network",
    "welcome.invalid_creds": "Invalid credentials. Please try again.",
    "welcome.password": "Password",
    "welcome.signin": "Sign In",
    "welcome.step1": "Tap <strong>Download App</strong> in the top-right corner.",
    "welcome.step2": "Install the EduMesh app on your phone.",
    "welcome.step3": "Open the app to browse and download all available resources.",
    "welcome.storage": "Storage",
    "welcome.storage.used": "{used} GB / {total} GB used",
    "welcome.storage_error": "Error loading storage info",
    "welcome.system_error": "Error loading system info",
    "welcome.teacher_login": "Educator Access",
    "welcome.teacher_subtitle": "Manage resources and monitor the mesh network.",
    "welcome.teacher_title": "Teacher Login",
    "welcome.tracking_privacy": "Study Tracking & Privacy",
    "welcome.troubleshooting": "Troubleshooting",
    "welcome.unavailable": "Unavailable",
    "welcome.username": "Username",
    "welcome.using_app": "Using the App",
    "welcome.vitals": "Hub Vitals",
    "welcome.courses_title": "Courses",
    "welcome.published": "Published",
    "welcome.drafts": "Drafts",
    "welcome.quick_stats": "Quick Stats",
    "welcome.stat_students": "Students",
    "welcome.stat_resources": "Resources",
    "welcome.stat_subjects": "Subjects",
    "welcome.uptime": "Uptime",
    "welcome.what_is": "What is Lumina Hub?",
    "welcome.what_is_body": "Lumina Hub is a local mesh server that delivers educational resources -- textbooks, lecture videos, and past papers -- directly to your device without using cellular data or internet.",
    "welcome_loading": "Loading…",
    "content.notif.select_subject": "Please select a subject.",
    "content.notif.topic_name_required": "Topic name is required.",
    "content.notif.topic_create_failed": "Failed to add topic.",
    "content.notif.topic_delete_failed": "Failed to delete topic.",
    "content.notif.topic_update_failed": "Failed to update topic.",
    "content.notif.resource_updated": "Resource updated.",
    "content.notif.resource_update_failed": "Failed to update resource.",
    "content.notif.load_failed": "Could not load resources.",
    "content.notif.title_required": "Title is required.",
    "content.topics.resource_count": "{count} resource(s) are assigned to this topic.",
    "content.topics.no_match": "No topics match your search.",
    "content.topics.select_subject": "Select subject...",
    "content.quiz.questions_empty": "No questions added yet.",
    "content.quiz.export_empty": "Add at least one question before exporting.",
    "content.quiz.file_description": "Quiz file",
    "content.quiz.import_invalid": "Invalid quiz file: no questions found.",
    "content.quiz.imported_count": "Imported {count} questions.",
    "content.quiz.import_parse_error": "Failed to parse quiz file.",
    "content.quiz.add_questions": "Add at least one question.",
    "content.quiz.quiz_created": "Quiz created.",
    "content.quiz.create_failed": "Failed to create quiz.",
    "content.quiz.save_failed": "Save failed: {message}",
    "content.quiz.edit_question": "Edit Question",
    "content.quiz.new_question": "New Question",
    "content.quiz.q_text_required": "Question text is required.",
    "content.quiz.answer_required": "Answer is required.",
    "content.quiz.options_required": "At least 2 options required.",
    "content.quiz.correct_required": "Select a correct answer.",
    "content.all_subjects_label": "All Subjects",
    "content.load_resources_http_error": "Could not load resources (HTTP {status}).",
    "content.library_no_resources": "No resources found.",
    "content.topics_general_no_topic": "General (No Topic)",
    "content.general": "General",
    "courses.general_subject": "General",
    "courses.quiz.export_empty": "Add at least one question before exporting.",
    "courses.quiz.import_invalid": "Invalid quiz file: no questions found.",
    "courses.quiz.imported_count": "Imported {count} questions.",
    "courses.quiz.import_parse_error": "Failed to parse quiz file.",
    "courses.quiz.save_failed": "Save failed: {message}",
    "index.uptime_na": "N/A",
    "settings.status_enabled": "Enabled",
    "settings.status_disabled": "Disabled",
    "danger.no_matching_grades": "No grades match your search.",
    "danger.no_subjects_found": "No subjects found.",
    "danger.delete_subject_btn": "Delete",
    "danger.subject_class_all": "All",
  }
};
/**
 * Look up a translated string for the current language.
 * Falls back to English if no translation exists.
 * @param {string} key - Dot-notation key (e.g. 'sidebar.home')
 * @param {Object} [params] - Optional interpolation values, using {name} syntax
 * @returns {string}
 */
function __(key, params) {
    const lang = TRANSLATIONS[currentLang];
    let val;
    if (lang && lang[key]) {
        val = lang[key];
    } else if (TRANSLATIONS.en && TRANSLATIONS.en[key]) {
        val = TRANSLATIONS.en[key];
    } else {
        return key;
    }
    if (params) {
        for (const k in params) {
            val = val.replace('{' + k + '}', params[k]);
        }
    }
    return val;
}

/**
 * Fetch and merge translations from an external JSON file.
 *
 * ## i18n merge pattern
 * Called once on page load to overlay the language-specific strings over the
 * defaults. If the file doesn't exist (e.g., translation not yet written), the
 * defaults in TRANSLATIONS.en are used without error. The merged table is stored
 * in TRANSLATIONS[code] for subsequent lookups.
 *
 * @param {string} code - Language code to load
 * @returns {Promise<void>}
 */
async function loadTranslations(code) {
    if (TRANSLATIONS[code] && code !== 'en') { applyLanguage(); return; }
    try {
        const res = await fetch('/static/lang/' + code + '.json', { credentials: 'include' });
        if (res.ok) {
            const data = await res.json();
            if (!TRANSLATIONS[code]) TRANSLATIONS[code] = {};
            for (const key in data) {
                TRANSLATIONS[code][key] = data[key];
            }
        }
        // Always ensure English fallback is fully loaded from en.json
        const enRes = await fetch('/static/lang/en.json', { credentials: 'include' });
        if (enRes.ok) {
            const enData = await enRes.json();
            if (!TRANSLATIONS.en) TRANSLATIONS.en = {};
            for (const key in enData) {
                TRANSLATIONS.en[key] = enData[key];
            }
        }
    } catch (e) {
        // File not found -- use defaults
    }
    applyLanguage();
}

/**
 * Apply the current language to the document.
 * Sets the lang attribute on <html> and updates any element with data-i18n attribute.
 * Also updates input placeholders and meta tags.
 */
function applyLanguage() {
    document.documentElement.setAttribute('lang', currentLang);
    document.querySelectorAll('[data-i18n]').forEach(function(el) {
        const key = el.getAttribute('data-i18n');
        const translated = __(key);
        if (translated !== key) {
            if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
                el.setAttribute('placeholder', translated);
            } else if (el.tagName === 'META') {
                el.setAttribute('content', translated);
            } else if (el.children.length > 0) {
                // Has child elements (e.g. SVG icons) -- find and update the trailing text node
                var last = el.lastChild;
                if (last && last.nodeType === 3) {
                    last.textContent = ' ' + translated;
                } else {
                    el.appendChild(document.createTextNode(' ' + translated));
                }
            } else {
                el.textContent = translated;
            }
        }
    });
    document.querySelectorAll('[data-i18n-title]').forEach(function(el) {
        const key = el.getAttribute('data-i18n-title');
        const translated = __(key);
        if (translated !== key) {
            el.setAttribute('title', translated);
        }
    });
    document.querySelectorAll('[data-i18n-aria-label]').forEach(function(el) {
        const key = el.getAttribute('data-i18n-aria-label');
        const translated = __(key);
        if (translated !== key) {
            el.setAttribute('aria-label', translated);
        }
    });
    document.querySelectorAll('[data-i18n-body]').forEach(function(el) {
        const key = el.getAttribute('data-i18n-body');
        const translated = __(key);
        if (translated !== key) {
            el.innerHTML = translated;
        }
    });
    document.querySelectorAll('[data-i18n-placeholder]').forEach(function(el) {
        const key = el.getAttribute('data-i18n-placeholder');
        const translated = __(key);
        if (translated !== key) {
            el.setAttribute('placeholder', translated);
        }
    });
    document.querySelectorAll('[data-i18n-data-label]').forEach(function(el) {
        const key = el.getAttribute('data-i18n-data-label');
        const translated = __(key);
        if (translated !== key) {
            el.setAttribute('data-label', translated);
        }
    });
    document.documentElement.setAttribute('data-i18n-ready', '');
    const label = document.getElementById('langPickerLabel');
    if (label) {
        const langObj = LANGUAGES.find(function(l){ return l.code === currentLang; });
        if (langObj) label.textContent = langObj.native;
    }
    document.dispatchEvent(new CustomEvent('languageChanged', {detail: {lang: currentLang}}));
}

/**
 * Switch the active language. Loads remote translations if not yet cached.
 * @param {string} code - Language code ('en', 'hi', 'kn', etc.)
 * @returns {Promise<void>}
 */
async function setLanguage(code) {
    if (code === currentLang) return;
    currentLang = code;
    localStorage.setItem('lumina-lang', code);
    if (!TRANSLATIONS[code] || code === 'en') {
        await loadTranslations(code);
    } else {
        applyLanguage();
    }
    closeLangPicker();
}

/**
 * Build and inject the language picker button in the top-right corner.
 *
 * ## Language switching flow
 * Creates a fixed-position button that opens a searchable dropdown of LANGUAGES.
 * The dropdown is built entirely in JS and appended to document.body. Selecting
 * a language calls setLanguage(), which triggers loadTranslations() + applyLanguage().
 * An overlay element behind the dropdown handles click-outside-to-close.
 * Only one instance is created (guarded by id check).
 */
function initLangPicker() {
    const existing = document.getElementById('langPickerWrap');
    if (existing) return;

    const wrap = document.createElement('div');
    wrap.id = 'langPickerWrap';
    wrap.style.cssText = 'position:fixed;top:0.75rem;right:0.75rem;z-index:500;display:flex;align-items:center;gap:0.5rem;';
    const style = document.createElement('style');
    style.textContent = '.lang-option:hover{background:var(--outline)!important}.lang-option.active-lang,.lang-option.active-lang:hover{background:var(--teal)!important;color:#fff!important}';
    document.head.appendChild(style);

    // Dark mode toggle button
    const themeBtn = document.createElement('button');
    themeBtn.id = 'themeToggleBtn';
    themeBtn.style.cssText = 'height:36px;width:36px;border-radius:18px;border:1px solid var(--outline);background:var(--bg-surface);color:var(--text-primary);cursor:pointer;display:flex;align-items:center;justify-content:center;box-shadow:0 1px 3px rgba(0,0,0,0.08);transition:all 0.2s;';
    function updateThemeIcon() {
        const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
        themeBtn.innerHTML = isDark
            ? '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg>'
            : '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>';
    }
    updateThemeIcon();
    themeBtn.addEventListener('click', function() { toggleTheme(); updateThemeIcon(); });
    themeBtn.addEventListener('mouseenter', function(){ themeBtn.style.background = 'var(--outline)'; });
    themeBtn.addEventListener('mouseleave', function(){ themeBtn.style.background = 'var(--bg-surface)'; });
    wrap.appendChild(themeBtn);

    const btn = document.createElement('button');
    btn.id = 'langPickerBtn';
    btn.setAttribute('aria-haspopup', 'listbox');
    btn.setAttribute('aria-expanded', 'false');
    btn.setAttribute('aria-controls', 'langDropdown');
    btn.setAttribute('aria-label', 'Language selection');
    btn.style.cssText = 'height:36px;border-radius:18px;border:1px solid var(--outline);background:var(--bg-surface);color:var(--text-primary);cursor:pointer;display:flex;align-items:center;gap:0.4rem;padding:0 0.75rem;box-shadow:0 1px 3px rgba(0,0,0,0.08);font-family:inherit;font-size:0.8rem;font-weight:700;transition:all 0.2s;';
    const initialLang = LANGUAGES.find(function(l){ return l.code === currentLang; }) || LANGUAGES[0];
    btn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width:16px;height:16px;flex-shrink:0;"><circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg><span id="langPickerLabel">' + esc(initialLang.native) + '</span>';
    btn.addEventListener('mouseenter', function(){ btn.style.background = 'var(--outline)'; });
    btn.addEventListener('mouseleave', function(){ btn.style.background = 'var(--bg-surface)'; });
    btn.addEventListener('click', function(e) { e.stopPropagation(); toggleLangPicker(); });

    wrap.appendChild(btn);
    document.body.appendChild(wrap);

    const overlay = document.createElement('div');
    overlay.id = 'langOverlay';
    overlay.addEventListener('click', closeLangPicker);
    document.body.appendChild(overlay);

    const dd = document.createElement('div');
    dd.id = 'langDropdown';
    dd.setAttribute('role', 'listbox');
    dd.setAttribute('aria-label', 'Available languages');
    dd.style.cssText = 'display:none;position:fixed;top:3.75rem;right:1rem;width:220px;background:var(--bg-surface);border:1px solid var(--outline);border-radius:10px;box-shadow:0 8px 24px rgba(0,0,0,0.2);z-index:1000;overflow:hidden;';
    dd.innerHTML = '<div style="padding:0.5rem;border-bottom:1px solid var(--outline);"><input id="langSearch" type="text" placeholder="' + __('sidebar.lang_search_placeholder') + '" style="width:100%;padding:0.4rem 0.6rem;font-size:0.8rem;font-family:inherit;border:1px solid var(--outline);border-radius:6px;background:var(--bg-surface);color:var(--text-primary);outline:none;box-sizing:border-box;"></div><div id="langList" style="overflow-y:auto;max-height:220px;"></div>';
    document.body.appendChild(dd);
    document.getElementById('langList').addEventListener('click', function _langClick(e) {
        const opt = e.target.closest('.lang-option');
        if (opt) setLanguage(opt.getAttribute('data-code'));
    });

    renderLangList('');

    let _langDebounce;
    document.getElementById('langSearch').addEventListener('input', function() {
        clearTimeout(_langDebounce);
        const val = this.value.toLowerCase();
        _langDebounce = setTimeout(() => renderLangList(val), 200);
    });
}

/**
 * Render the language list inside the dropdown, filtered by search query.
 * Highlights the active language with teal background.
 * @param {string} query - Lowercased search filter string
 * @returns {void}
 */
function renderLangList(query) {
    const list = document.getElementById('langList');
    if (!list) return;
    const filtered = query ? LANGUAGES.filter(function(l){ return l.name.toLowerCase().indexOf(query) !== -1 || l.native.indexOf(query) !== -1 || l.code.indexOf(query) !== -1; }) : LANGUAGES;
    list.innerHTML = filtered.map(function(l) {
        const active = l.code === currentLang;
        return '<div class="lang-option' + (active ? ' active-lang' : '') + '" data-code="' + l.code + '" role="option" aria-selected="' + active + '" style="padding:0.5rem 0.75rem;cursor:pointer;font-size:0.85rem;display:flex;justify-content:space-between;align-items:center;border-radius:6px;"><span>' + esc(l.native) + '</span><span style="font-size:0.7rem;opacity:0.6;">' + esc(l.name) + '</span></div>';
    }).join('');
}

/**
 * Toggle the language picker dropdown open/closed.
 * Shows/hides the dropdown and its backing overlay.
 */
function toggleLangPicker() {
    const dd = document.getElementById('langDropdown');
    try { dd.style.display = dd.style.display === 'block' ? 'none' : 'block'; } catch(e){ return; }
    const ov = document.getElementById('langOverlay');
    if (ov) ov.style.display = dd.style.display;
    if (dd.style.display === 'block') {
        renderLangList('');
        setTimeout(function() { const s = document.getElementById('langSearch'); if(s) s.focus(); }, 50);
    }
}

/** Close the language picker dropdown and overlay. */
function closeLangPicker() {
    const dd = document.getElementById('langDropdown');
    const ov = document.getElementById('langOverlay');
    if (dd) dd.style.display = 'none';
    if (ov) ov.style.display = 'none';
}

/* ── Theme ───────────────────────────────────────────────────────────────── */

/**
 * Get the preferred theme based on localStorage or system preference.
 * Checks localStorage first, then falls back to prefers-color-scheme media query.
 * @returns {string} 'light' or 'dark'
 */
function getPreferredTheme() {
    const stored = localStorage.getItem('lumina-theme');
    if (stored) return stored;
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

/**
 * Apply a theme to the document and persist to localStorage.
 * Updates the data-theme attribute on <html>, the theme toggle icon,
 * and the theme toggle label text.
 * @param {string} theme - 'light' or 'dark'
 * @returns {void}
 */
function setTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('lumina-theme', theme);
    const icon = document.getElementById('themeIcon');
    const label = document.getElementById('themeLabel');
    if (icon) {
        if (theme === 'dark') {
            icon.innerHTML = '<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>';
        } else {
            icon.innerHTML = '<circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/>';
        }
    }
    if (label) label.textContent = theme === 'dark' ? __('sidebar.light_mode') : __('sidebar.dark_mode');
}

/** Toggle between light and dark themes based on current preference. */
function toggleTheme() { setTheme(getPreferredTheme() === 'dark' ? 'light' : 'dark'); }

/* ── Notifications ───────────────────────────────────────────────────────── */

/**
 * Show a temporary toast notification at the bottom of the page.
 * Toast auto-dismisses after 3 seconds with a fade-out animation.
 * @param {string} msg - Message text to display
 * @param {boolean} isError - If true, uses danger/red background; otherwise success/green
 * @returns {void}
 */
function showAlert(msg, isError) {
    const container = document.getElementById('globalToastContainer');
    if (!container) return;
    const toast = document.createElement('div');
    toast.style.cssText = 'background:' + (isError ? 'var(--danger)' : 'var(--success)') + ';color:#fff;padding:0.85rem 1.25rem;border-radius:8px;font-weight:600;font-size:0.85rem;box-shadow:0 4px 12px rgba(0,0,0,0.2);pointer-events:auto;animation:slideIn 0.25s ease;';
    toast.textContent = msg;
    container.appendChild(toast);
    setTimeout(() => { toast.style.opacity = '0'; toast.style.transition = 'opacity 0.3s'; setTimeout(() => toast.remove(), 300); }, 3000);
}

/**
 * Show an inline notification element by id.
 * Shows a pre-existing notification div with success or error styling.
 * Auto-hides after 4 seconds.
 * @param {string} notifId - DOM id of the notification element
 * @param {string} msg - Message text to display
 * @param {boolean} isError - If true, uses danger styling; otherwise success
 * @returns {void}
 */
function showNotification(notifId, msg, isError) {
    const el = document.getElementById(notifId);
    if (!el) return;
    el.textContent = msg;
    el.style.display = 'block';
    el.style.background = isError ? 'rgba(229,62,62,0.08)' : 'rgba(56,161,105,0.08)';
    el.style.color = isError ? 'var(--danger)' : 'var(--success)';
    el.style.borderColor = isError ? 'var(--danger)' : 'var(--success)';
    setTimeout(() => { el.style.display = 'none'; }, 4000);
}

/**
 * Render the logged-in user display in the sidebar.
 * Shared between the synchronous cached render and the async whoami fetch.
 * @param {string} username
 * @param {string} [role] - Optional role (admin/teacher)
 * @returns {void}
 */
function renderUserInfo(username, role) {
    var el = document.getElementById('userInfo');
    if (!el || !role) return;
    el.innerHTML = '<div style="font-weight: 800; font-size: 1.2rem; color: #fff; letter-spacing: -0.015em;">' + esc(role.toUpperCase()) + '</div>';
}

/**
 * Shows a modal confirm dialog with configurable danger/teal styling.
 * Returns a Promise that resolves to true (confirmed) or false (cancelled).
 * @param {string} title - Modal title text
 * @param {string} message - Modal body text
 * @param {boolean} isDanger - If true, danger (red) styling; if false, teal
 * @param {string} [confirmText] - Optional text for the confirm button
 * @returns {Promise<boolean>}
 */
/**
 * Focus trap utility for accessible modals.
 * Traps focus within the given element, handles Escape key, and restores focus on exit.
 * @param {HTMLElement} modal - The modal element to trap focus within
 * @param {HTMLElement} triggerEl - The element that triggered the modal (for focus restoration)
 * @returns {Object} Object with activate(), deactivate() methods
 */
function createFocusTrap(modal, triggerEl) {
    var focusableSelectors = 'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])';
    var focusableElements = [];
    var firstFocusable = null;
    var lastFocusable = null;
    var keydownHandler = null;

    function updateFocusableElements() {
        focusableElements = Array.prototype.slice.call(modal.querySelectorAll(focusableSelectors))
            .filter(function(el) { return el.offsetParent !== null && !el.disabled; });
        firstFocusable = focusableElements[0];
        lastFocusable = focusableElements[focusableElements.length - 1];
    }

    function handleKeydown(e) {
        if (e.key === 'Escape') {
            e.preventDefault();
            deactivate();
            return;
        }
        if (e.key !== 'Tab') return;
        updateFocusableElements();
        if (focusableElements.length === 0) return;
        if (e.shiftKey) {
            if (document.activeElement === firstFocusable) {
                e.preventDefault();
                lastFocusable.focus();
            }
        } else {
            if (document.activeElement === lastFocusable) {
                e.preventDefault();
                firstFocusable.focus();
            }
        }
    }

    function activate() {
        updateFocusableElements();
        if (firstFocusable) firstFocusable.focus();
        keydownHandler = handleKeydown;
        document.addEventListener('keydown', keydownHandler);
    }

    function deactivate() {
        document.removeEventListener('keydown', keydownHandler);
        if (triggerEl && typeof triggerEl.focus === 'function') {
            triggerEl.focus();
        }
    }

    return { activate: activate, deactivate: deactivate };
}

/**
 * Shows a confirmation modal with the given title and message.
 * Returns a promise that resolves to true (confirmed) or false (cancelled).
 * @param {string} title - Modal title
 * @param {string} message - Modal body text
 * @param {boolean} [isDanger=true] - If true, uses danger (red) styling; if false, teal
 * @param {string} [confirmText] - Optional text for the confirm button
 * @returns {Promise<boolean>}
 */
function showConfirm(title, message, isDanger, confirmText) {
    if (isDanger === undefined) isDanger = true;
    return new Promise(function(resolve) {
        var modal = document.getElementById('globalConfirmModal');
        var titleEl = document.getElementById('confirmModalTitle');
        var textEl = document.getElementById('confirmModalText');
        var confirmBtn = document.getElementById('confirmConfirmBtn');
        var cancelBtn = document.getElementById('confirmCancelBtn');
        var iconEl = document.getElementById('confirmModalIcon');
        if (!modal || !titleEl || !textEl || !confirmBtn || !cancelBtn) { resolve(false); return; }
        titleEl.innerText = title;
        textEl.innerText = message;
        if (isDanger) {
            confirmBtn.style.background = 'var(--danger)';
            confirmBtn.style.borderColor = 'var(--danger)';
            iconEl.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="28" height="28" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" x2="12" y1="9" y2="13"/><line x1="12" x2="12.01" y1="17" y2="17"/></svg>';
            iconEl.style.background = 'transparent';
            iconEl.style.color = 'var(--danger)';
            modal.firstElementChild.style.border = '2px solid var(--danger)';
        } else {
            confirmBtn.style.background = 'var(--teal)';
            confirmBtn.style.borderColor = 'var(--teal)';
            iconEl.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="28" height="28" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"></circle><polyline points="12 16 16 12 12 8"></polyline><line x1="8" y1="12" x2="16" y2="12"></line></svg>';
            iconEl.style.background = 'transparent';
            iconEl.style.color = 'var(--teal)';
            modal.firstElementChild.style.border = '1px solid var(--outline)';
        }
        if (confirmText) confirmBtn.innerText = confirmText;

        // Capture the element that triggered the modal for focus restoration
        var triggerEl = document.activeElement;

        modal.classList.remove('hidden');

        // Set up focus trap
        var focusTrap = createFocusTrap(modal, triggerEl);
        focusTrap.activate();

        var _confirmHandler = function() { cleanup(true); };
        var _cancelHandler = function() { cleanup(false); };
        confirmBtn.addEventListener('click', _confirmHandler);
        cancelBtn.addEventListener('click', _cancelHandler);

        function cleanup(value) {
            focusTrap.deactivate();
            modal.classList.add('hidden');
            confirmBtn.removeEventListener('click', _confirmHandler);
            cancelBtn.removeEventListener('click', _cancelHandler);
            resolve(value);
        }
    });
}

/* ── Auth ─────────────────────────────────────────────────────────────────── */
/** @type {string} Username of the currently logged-in user. Defaults to 'admin' until /whoami responds. */
let loggedInUser = 'admin';
/** @type {string} Role of the logged-in user ('admin' or 'teacher'). Defaults to 'admin'. */
let userRole = 'admin';
/** @type {boolean} Whether the default 'admin' login is still enabled. */
let adminDefaultEnabled = true;

/**
 * ── Auth / Session Flow ──────────────────────────────────────────────────────
 *
 * The Lumina Hub uses cookie-based session authentication:
 *  1. Login: POST /token (teacher/admin) or POST /student/token (student)
 *     → Server sets `lumina_session` (httponly) cookie + returns tokens in body.
 *  2. Session persistence: The browser sends the cookie automatically on every
 *     request. No Authorization header needed for cookie-based auth.
 *  3. WhoAmI: GET /whoami reads the cookie server-side and returns {username, role}.
 *     This is called on every dashboard page load to verify the session.
 *  4. Cached user: sessionStorage('lumina-user') is set on every successful
 *     /whoami response and rendered immediately by the synchronous IIFE below
 *     to eliminate the flash of empty userInfo on page navigation.
 *  5. Logout: GET /logout (or POST) deletes the session from the DB and clears
 *     the cookie. Redirects to /welcome.
 *  6. Session expiry: The server returns 401. The frontend redirects to
 *     /static/error?reason=session_expired.
 *  7. Force password reset: If the server returns reset_required=1, the user
 *     is shown a forced password reset modal before accessing any page.
 */

/**
 * Immediately renders the cached username from sessionStorage on script load.
 * Eliminates the flash of empty userInfo area while loadWhoAmI() is in flight.
 * Runs synchronously as an IIFE before any async fetch.
 */
(function renderCachedUser() {
    const cached = sessionStorage.getItem('lumina-user');
    const cachedRole = sessionStorage.getItem('lumina-role');
    if (cached) {
        loggedInUser = cached;
        userRole = cachedRole || 'admin';
        renderUserInfo(cached, cachedRole);
    }
})();

/**
 * Fetches the currently logged-in user's info from /whoami.
 * Updates the userInfo sidebar element and caches the username to sessionStorage.
 * Called on DOMContentLoaded by each page that has a sidebar.
 *
 * ## Cached user pattern
 * This async function fetches the server-side session. While it's in flight,
 * the synchronous IIFE above renders the cached username from the previous
 * page load. Once this resolves, it overwrites with fresh data. If the session
 * is expired (non-ok response), the user is redirected to the error page.
 * @returns {Promise<void>}
 */
async function loadWhoAmI() {
    try {
        const res = await fetch('/whoami', { credentials: 'include' });
        if (!res.ok) {
            window.location.href = '/static/error?reason=session_expired';
            return;
        }
        const data = await res.json();
        loggedInUser = data.username;
        userRole = data.role;
        sessionStorage.setItem('lumina-user', data.username);
        sessionStorage.setItem('lumina-role', data.role);
        renderLayout();
        renderUserInfo(data.username, data.role);
    } catch (e) {
        console.error('Error loading whoami info', e);
    }
}

/**
 * Checks whether the current session has reset_required=1.
 * If so, shows the force password reset modal.
 * Sets loggedInUser from /teacher/me response.
 */
async function checkSelfResetRequired() {
    try {
        var res = await fetch('/teacher/me', { credentials: 'same-origin' });
        if (res.ok) {
            var me = await res.json();
            loggedInUser = me.username;
            if (me.reset_required === 1) {
                var resetModal = document.getElementById('forceResetModal');
                resetModal.classList.remove('hidden');
                // Activate focus trap for accessibility
                var focusTrap = createFocusTrap(resetModal, null);
                focusTrap.activate();
                // Store for cleanup on submit
                resetModal._focusTrap = focusTrap;
            }
        }
    } catch (e) {
        console.error("Error checking reset state", e);
    }
}

/**
 * Submits the force password reset. Validates passwords, then
 * sends POST to /teacher/force-change-password. Reloads page on success.
 */
async function submitForcePasswordReset() {
    var newPwd = document.getElementById('forceNewPwd').value;
    var confirmPwd = document.getElementById('forceConfirmPwd').value;
    if (!newPwd || !confirmPwd) {
        return showNotification('forceResetNotif', __('content.notif.pwd_fields_required'), true);
    }
    if (newPwd !== confirmPwd) {
        return showNotification('forceResetNotif', __('content.notif.pwd_mismatch'), true);
    }
    try {
        var res = await fetch('/teacher/force-change-password', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username: loggedInUser || 'admin', new_password: newPwd })
        });
        if (res.ok) {
            showNotification('forceResetNotif', __('content.notif.pwd_updated'), false);
            setTimeout(function() { location.reload(); }, 1500);
        } else {
            var err = await res.json();
            showNotification('forceResetNotif', err.detail || __('content.notif.pwd_update_failed'), true);
        }
    } catch (e) {
        showNotification('forceResetNotif', __('content.notif.connection_error'), true);
    }
}

/* ── Mobile Menu ─────────────────────────────────────────────────────────── */

/** Toggle the mobile sidebar open/closed by toggling .open and .active classes. */
function toggleMobileMenu() {
    const sidebar = document.querySelector('aside');
    const overlay = document.querySelector('.mobile-overlay');
    if (sidebar) sidebar.classList.toggle('open');
    if (overlay) overlay.classList.toggle('active');
}

/* ── Active nav highlighting ─────────────────────────────────────────────── */

/**
 * Manually highlights a sidebar nav item and its matching bottom-nav item.
 * Removes 'active' from all nav items first.
 * @param {string} navId - The DOM id of the nav item to highlight (e.g. 'nav-home').
 * @returns {void}
 */

/**
 * Renders the sidebar (<aside>) and bottom nav (#bottomNav) into their container
 * elements. Called once on DOMContentLoaded. Eliminates identical sidebar/nav
 * HTML that was duplicated across all 8 dashboard pages.
 */
function renderLayout() {
    if (window.__luminaLayoutRendered) return;
    if (document.getElementById('welcome-content')) return;
    window.__luminaLayoutRendered = true;
    var aside = document.querySelector('aside');
    var bottomNav = document.getElementById('bottomNav');
    if (!aside) return;
    // Add ARIA attributes to sidebar
    aside.setAttribute('role', 'navigation');
    aside.setAttribute('aria-label', 'Main navigation');
    // Create bottomNav if missing (static pages don't have it)
    if (!bottomNav) {
        bottomNav = document.createElement('div');
        bottomNav.id = 'bottomNav';
        bottomNav.className = 'bottom-nav';
        document.body.appendChild(bottomNav);
    }
    // Add ARIA attributes to bottom nav
    bottomNav.setAttribute('role', 'navigation');
    bottomNav.setAttribute('aria-label', 'Bottom navigation');

    // Always re-render (role may have changed since last render)

    var path = location.pathname.replace(/\/+$/, '');
    var mapping = { '/static/index':'home','/static/courses':'courses','/static/manage-content':'content','/static/manage-settings':'settings','/static/students':'students','/static/student-detail':'students','/static/manage-help':'help','/static/manage-danger':'danger' };
    var key = mapping[path] || '';
    var useAccount = key === 'settings' && path === '/static/manage-settings';

    function idFor(k) { return k === 'settings' ? 'account' : k; }

    /* All nav-item SVGs (inline, one per entry) */
    var HOME_SVG='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/></svg>';
    var FILE_SVG='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/></svg>';
    var LOCK_SVG='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="11" x="3" y="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>';
    var COURSES_SVG='<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/></svg>';
    var USERS_SVG='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>';
    var HELP_SVG='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/><path d="M12 17h.01"/></svg>';
    var DANGER_SVG='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="danger-icon"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" x2="12" y1="9" y2="13"/><line x1="12" x2="12.01" y1="17" y2="17"/></svg>';
    var LOGOUT_SVG='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" x2="9" y1="12" y2="12"/></svg>';
    var GEAR_SVG='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>';

    var navList = [
        { k:'home',      href:'/static/index',               svg:HOME_SVG,      sideLabel:'Home',           botLabel:'Home' },
        { k:'content',   href:'/static/manage-content',      svg:FILE_SVG,      sideLabel:'Content Manager',botLabel:'Content' },
        { k:'courses',   href:'/static/courses',             svg:COURSES_SVG,   sideLabel:'Courses',        botLabel:'Courses' },
        { k:'students',  href:'/static/students',            svg:USERS_SVG,     sideLabel:'Students',       botLabel:'Students' },
        { k:'help',      href:'/static/manage-help#teacher-guide',svg:HELP_SVG,sideLabel:'Teacher Guide', botLabel:'Guide' },
        { k:'settings',  href:'/static/manage-settings',     svg:GEAR_SVG,      sideLabel:'Settings',       botLabel:'Settings' },
    ];
    if (userRole === 'admin') {
        navList.push({ k:'danger',   href:'/static/manage-danger',       svg:DANGER_SVG, sideLabel:'Danger Zone',    botLabel:'Danger' });
    }

    var sbNav = '', btmNav = '';
    for (var i = 0; i < navList.length; i++) {
        var n = navList[i];
        var active = n.k === key;
        var id = idFor(n.k);
        var danger = n.k === 'danger' ? ' danger' : '';
        sbNav += '<a href="' + n.href + '" class="nav-item' + (active ? ' active' : '') + danger + '" id="nav-' + id + '">' + n.svg + '<span data-i18n="sidebar.' + n.k + '">' + n.sideLabel + '</span></a>\n            ';
        btmNav += '<a href="' + n.href + '" class="bottom-nav-item' + (active ? ' active' : '') + danger + '" id="bottom-nav-' + id + '">' + n.svg + '<span data-i18n="sidebar.' + n.k + '">' + n.botLabel + '</span></a>\n        ';
    }

    aside.innerHTML =
        '<a href="/static/index" class="sidebar-brand-horizontal">' +
            '<img class="logo-light" src="/static/assets/Horizontal Transparent Lightmode Icon.svg" style="width:100%;height:auto;max-height:90px;" alt="Lumina">' +
            '<img class="logo-dark" src="/static/assets/Horizontal Transparent Darkmode Icon.svg" style="width:100%;height:auto;max-height:90px;" alt="Lumina">' +
        '</a>' +
        '<div id="userInfo" class="sidebar-subtitle" style="margin-top:0.5rem;font-size:0.85rem;color:var(--on-primary);"></div>' +
        '<div class="sidebar-divider"></div>' +
        '<nav>\n            ' + sbNav + '</nav>' +
        '<div class="nav-spacer"></div>' +
        '<a href="/logout" class="nav-logout" onclick="sessionStorage.clear()">' + LOGOUT_SVG + '<span data-i18n="sidebar.logout">Log out</span></a>';

    // bottom nav gets a logout item at the end
    btmNav += '<a href="/logout" class="bottom-nav-item" id="bottom-nav-logout" onclick="sessionStorage.clear()">' + LOGOUT_SVG + '<span data-i18n="sidebar.logout">Log out</span></a>';
    bottomNav.innerHTML = btmNav;
}

/**
 * Injects global modal HTML (confirm modal, force-reset modal) into document.body.
 * Called once on DOMContentLoaded. Creates the modals if they don't already exist.
 */
function renderModals() {
    if (document.getElementById('globalConfirmModal')) return;

    var confirmModal = document.createElement('div');
    confirmModal.id = 'globalConfirmModal';
    confirmModal.className = 'hidden popup';
    confirmModal.setAttribute('role', 'dialog');
    confirmModal.setAttribute('aria-modal', 'true');
    confirmModal.setAttribute('aria-labelledby', 'confirmModalTitle');
    confirmModal.style.cssText = 'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(15,23,42,0.65); backdrop-filter: blur(4px); display: flex; align-items: center; justify-content: center; z-index: 30000; transition: all 0.3s ease;';
    confirmModal.innerHTML =
        '<div style="background: var(--surface); color: var(--on-surface); border-radius: var(--radius); padding: 2.25rem; max-width: 440px; width: 90%; box-shadow: var(--card-shadow-hover); border: 1px solid var(--outline); text-align: center;">' +
        '<div id="confirmModalIcon" style="margin: 0 auto 1.25rem; text-align: center;"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="28" height="28" fill="none" stroke="var(--danger)" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" x2="12" y1="9" y2="13"/><line x1="12" x2="12.01" y1="17" y2="17"/></svg></div>' +
        '<h3 id="confirmModalTitle" style="font-size: 1.25rem; font-weight: 800; color: var(--on-surface); margin-top: 0; margin-bottom: 0.5rem;">Confirm Action</h3>' +
        '<p id="confirmModalText" style="color: var(--on-surface); opacity: 0.7; font-size: 0.875rem; line-height: 1.5; margin-bottom: 1.75rem;">Are you sure you want to proceed?</p>' +
        '<div style="display: flex; gap: 0.75rem; justify-content: flex-end; border-top: 1px solid var(--outline); padding-top: 1.25rem;">' +
        '<button id="confirmCancelBtn" class="btn btn-outline" style="border-color: var(--outline); color: var(--on-surface); background: transparent; padding: 0.625rem 1.25rem;">Cancel</button>' +
        '<button id="confirmConfirmBtn" class="btn" style="background: var(--danger); color: #fff; padding: 0.625rem 1.25rem;">Confirm</button></div></div>';

    var resetModal = document.createElement('div');
    resetModal.id = 'forceResetModal';
    resetModal.className = 'hidden popup';
    resetModal.setAttribute('role', 'dialog');
    resetModal.setAttribute('aria-modal', 'true');
    resetModal.setAttribute('aria-labelledby', 'forceResetModalTitle');
    resetModal.style.cssText = 'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(15,23,42,0.8); backdrop-filter: blur(6px); display: flex; align-items: center; justify-content: center; z-index: 20000;';
    resetModal.innerHTML =
        '<div style="background: var(--surface); color: var(--on-surface); border-radius: var(--radius); padding: 2.5rem; max-width: 440px; width: 90%; box-shadow: var(--card-shadow-hover); border: 1px solid var(--outline); text-align: center;">' +
        '<div style="margin: 0 auto 1.5rem; text-align: center;"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="var(--warning)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="11" x="3" y="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg></div>' +
        '<h3 id="forceResetModalTitle" style="font-size: 1.35rem; font-weight: 800; color: var(--on-surface); margin-top: 0; margin-bottom: 0.5rem;">Password Reset Required</h3>' +
        '<p style="color: var(--on-surface); opacity: 0.7; font-size: 0.875rem; line-height: 1.5; margin-bottom: 1.5rem;">An administrator has forced a password reset on your account. You must change your password before you can proceed.</p>' +
        '<div id="forceResetNotif" style="display: none; padding: 0.75rem 1rem; margin-bottom: 1rem; border-radius: 6px; font-weight: 700; font-size: 0.85rem; text-align: center;"></div>' +
        '<div class="form-group" style="text-align: left; margin-bottom: 1rem;">' +
        '<label for="forceNewPwd" style="display: block; font-size: 0.75rem; font-weight: 700; color: var(--on-surface); opacity: 0.7; margin-bottom: 0.375rem;">New Password</label>' +
        '<input type="password" id="forceNewPwd" placeholder="Enter new password" style="width: 100%; padding: 0.65rem; border: 1px solid var(--outline); border-radius: 6px; background: var(--surface); color: var(--on-surface);">' +
        '<div style="font-size:0.75rem;color:var(--text-muted);margin-top:0.375rem;">Must be 8+ chars, with uppercase, lowercase & a digit.</div></div>' +
        '<div class="form-group" style="text-align: left; margin-bottom: 1.5rem;">' +
        '<label for="forceConfirmPwd" style="display: block; font-size: 0.75rem; font-weight: 700; color: var(--on-surface); opacity: 0.7; margin-bottom: 0.375rem;">Confirm New Password</label>' +
        '<input type="password" id="forceConfirmPwd" placeholder="Confirm new password" style="width: 100%; padding: 0.65rem; border: 1px solid var(--outline); border-radius: 6px; background: var(--surface); color: var(--on-surface);"></div>' +
        '<button id="btn-submitForcePasswordReset" class="btn btn-primary" style="width: 100%; padding: 0.75rem; font-size: 0.875rem;">Update and Continue</button></div>';

    document.body.appendChild(confirmModal);
    document.body.appendChild(resetModal);
}

/**
 * Auto-detects the current page from location.pathname and highlights the correct
 * sidebar nav item and bottom-nav item. Runs once on DOMContentLoaded.
 * Path-to-key mapping covers all static dashboard pages.
 */
function initNav() {
    if (document.getElementById('welcome-content')) return;
    renderLayout();
    const path = location.pathname.replace(/\/+$/, '');
    const mapping = {
        '/static/index': 'home',
        '/static/courses': 'courses',
        '/static/manage-content': 'content',
        '/static/manage-settings': 'settings',
        '/static/students': 'students',
        '/static/student-detail': 'students',
        '/static/manage-help': 'help',
        '/static/manage-danger': 'danger',
    };
    const key = mapping[path] || '';
    if (key) {
        const suffix = (key === 'settings' && path === '/static/manage-settings') ? 'account' : key;
        document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
        document.querySelectorAll('.bottom-nav-item').forEach(el => el.classList.remove('active'));
        const navEl = document.getElementById('nav-' + suffix);
        if (navEl) navEl.classList.add('active');
        const bottomEl = document.getElementById('bottom-nav-' + suffix);
        if (bottomEl) bottomEl.classList.add('active');
    }
}



/* ── SPA Navigation ────────────────────────────────────────────────────────── */
const _pageInitRegistry = {};
let _isNavigating = false;

function initCurrentPage() {
    const path = location.pathname.replace(/\/+$/, '');
    const mapping = {
        '/static/index': 'home',
        '/static/courses': 'courses',
        '/static/manage-content': 'content',
        '/static/manage-settings': 'settings',
        '/static/students': 'students',
        '/static/student-detail': 'student-detail',
        '/static/manage-help': 'help',
        '/static/manage-danger': 'danger',
    };
    const key = mapping[path];
    if (key && _pageInitRegistry[key]) _pageInitRegistry[key]();
}

async function navigateTo(url, pushHistory) {
    if (pushHistory === undefined) pushHistory = true;
    if (url === location.href) return;
    if (_isNavigating) return; // prevent concurrent navigation
    _isNavigating = true;
    try {
        const res = await fetch(url, { credentials: 'include' });
        if (!res.ok) { window.location.href = url; return; }
        const html = await res.text();
        const doc = new DOMParser().parseFromString(html, 'text/html');
        const newApp = doc.getElementById('app-content');
        const currApp = document.getElementById('app-content');
        if (newApp && currApp) currApp.innerHTML = newApp.innerHTML;
        if (pushHistory) history.pushState({ url: url }, '', url);
        const newTitle = doc.querySelector('title');
        if (newTitle) document.title = newTitle.textContent;
        initNav();
        await loadTranslations(currentLang);
        applyLanguage();
        // Re-evaluate inline scripts from fetched page to register page inits
        doc.querySelectorAll('script').forEach(function(script) {
            if (!script.src) { try { eval(script.textContent); } catch(e) {} }
        });
        loadWhoAmI();
        initCurrentPage();
    } catch (e) {
        console.error('SPA navigation failed:', e);
        window.location.href = url;
    } finally {
        _isNavigating = false;
    }
}

window.addEventListener('popstate', function(e) {
    if (e.state && e.state.url) navigateTo(e.state.url, false);
});

document.addEventListener('DOMContentLoaded', function() {
    try {
        initNav();
        renderModals();
        if (!document.getElementById('welcomeLangBtn') && !document.querySelector('.lang-nav-wrap')) {
            initLangPicker();
        }
    } catch(e) {
        console.error('DOMContentLoaded init error:', e);
    }

    loadTranslations(currentLang).then(function() {
        applyLanguage();
        if (document.getElementById('app-content')) {
            loadWhoAmI();
        }
        initCurrentPage();
    }).catch(function(e) {
        console.error('DOMContentLoaded loadTranslations error:', e);
        applyLanguage();
        if (document.getElementById('app-content')) {
            loadWhoAmI();
        }
        initCurrentPage();
    });

    // Global mobile menu toggle (works for both JS-created and static buttons)
    document.getElementById('btn-toggleMobileMenu')?.addEventListener('click', toggleMobileMenu);
    document.getElementById('overlay-toggleMobileMenu')?.addEventListener('click', toggleMobileMenu);
});

/* Intercept sidebar and bottom-nav nav clicks for SPA */
document.addEventListener('click', function(e) {
    var link = e.target.closest('a');
    if (!link) return;
    var href = link.getAttribute('href');
    if (!href || href.startsWith('http') || href.startsWith('//') || href.startsWith('#') || href.startsWith('/logout') || link.hasAttribute('download')) return;
    var isNav = href.startsWith('/static/');
    if (isNav) {
        e.preventDefault();
        navigateTo(href);
    }
});
