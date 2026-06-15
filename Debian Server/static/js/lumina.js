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
 * Safely construct a URL from a resource filename.
 * Allows absolute paths and http(s) URLs; otherwise prefixes with /files/.
 * @param {string} url - Raw URL or filename
 * @returns {string} Safe URL string
 */
function safeUrl(url) {
    if (!url) return '#';
    if (url.startsWith('/') || url.startsWith('http://') || url.startsWith('https://')) return url;
    return '/files/' + encodeURIComponent(url);
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
        "app.tagline": "Your Offline Learning Network",
        "app.title": "Lumina Hub",
        "content.add_subject_button": "Add Subject",
        "content.add_subject_label_class": "Class/Grade",
        "content.add_subject_label_name": "Subject Name",
        "content.add_subject_label_symbol": "Symbol",
        "content.add_subject_placeholder_class": "e.g. Grade 10",
        "content.add_subject_placeholder_name": "e.g. Physics",
        "content.add_subject_symbol_calculator": "∑ Calculator",
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
        "content.upload_option_kiwix": "Kiwix",
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
        "danger.cancel": "Cancel",
        "danger.confirm": "Confirm",
        "danger.confirm.delete_admin": "Are you sure you want to delete admin profile \"{username}\"?",
        "danger.confirm.delete_admin_title": "Delete Admin Profile",
        "danger.confirm.delete_btn": "Delete",
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
        "danger.empty_admins": "No admin accounts registered yet.",
        "danger.empty_students": "No student accounts registered yet.",
        "danger.empty_teachers": "No teacher accounts registered yet.",
        "danger.error.both_fields": "Please fill in both fields.",
        "danger.error.connection": "Error connecting to server.",
        "danger.error.create_admin_failed": "Could not create admin account.",
        "danger.error.create_student_failed": "Could not create student.",
        "danger.error.create_teacher_failed": "Could not create teacher account.",
        "danger.error.name_username_required": "Please fill in name and username.",
        "danger.error.passwords_match": "Passwords do not match.",
        "danger.error.required_fields": "Please fill in all required fields.",
        "danger.error.update_failed": "Could not update password.",
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
        "danger.notif.student_created": "Student \"{name}\" created successfully.",
        "danger.notif.student_deleted": "Student \"{name}\" deleted.",
        "danger.notif.student_pwd_reset": "Password for student \"{name}\" reset to default.",
        "danger.notif.student_pwd_reset_failed": "Could not reset student password.",
        "danger.notif.teacher_pwd_reset": "Teacher \"{username}\" password reset to default.",
        "danger.notif.teacher_pwd_reset_failed": "Could not reset teacher password.",
        "danger.page_title": "Lumina Hub | Danger Zone",
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
        "help.admin_body": "<ul>\n    <li><strong>Danger Zone</strong> &mdash; Reset all data, force admin password reset, set log retention, and view audit logs.</li>\n    <li><strong>Settings</strong> &mdash; Toggle dark mode, view system info (Python version, database path, hostname).</li>\n    <li><strong>Setup script</strong> &mdash; Run <code>sudo ./setup_hub.sh</code> to provision the hotspot, install dependencies, and configure the systemd service from scratch.</li>\n</ul>",
        "help.getting_started": "Getting Started",
        "help.getting_started_body": "<ul>\n    <li><strong>Connect</strong> &mdash; Join the <strong>EduMesh</strong> Wi-Fi hotspot broadcast by the Hub laptop. The captive portal opens automatically.</li>\n    <li><strong>Install the app</strong> &mdash; On the welcome page, download the EduMesh APK and install it on your Android phone. Enable \"Install from Unknown Sources\" if prompted.</li>\n    <li><strong>Register</strong> &mdash; Open the app, enter your name, and you are in. The Hub assigns you a permanent student ID.</li>\n    <li><strong>Start learning</strong> &mdash; Browse textbooks, videos, and other resources. Download them to use offline.</li>\n</ul>",
        "help.page_title": "Lumina Hub | Help & Documentation",
        "help.subtitle": "How to use the Lumina Hub and EduMesh app.",
        "help.teachers": "For Teachers",
        "help.teachers_body": "<ul>\n    <li><strong>Upload resources</strong> &mdash; Go to Content Manager, select a PDF or video, give it a title and subject, and click Upload. Resources are available to all students immediately.</li>\n    <li><strong>Manage content</strong> &mdash; Filter by subject and grade to find resources. Click delete to remove any resource and its file.</li>\n    <li><strong>View students</strong> &mdash; Go to Students to see all registered students, filter by grade, or search by name. Each card shows weekly study time, streak, and saved resources.</li>\n    <li><strong>Detailed analytics</strong> &mdash; Click a student to see their full profile with study time breakdown and resource count.</li>\n    <li><strong>Change your password</strong> &mdash; Go to Account Settings to update your login credentials, display name, and department.</li>\n</ul>",
        "help.title": "Help & Instructions",
        "help.tracking": "Student Tracking",
        "help.tracking_body": "<ul>\n    <li><strong>Study time</strong> &mdash; The app tracks focused study sessions using the built-in timer. Total weekly minutes are synced to the Hub.</li>\n    <li><strong>Streak</strong> &mdash; Consecutive days the student uses the app. Calculated on the phone and synced to the Hub.</li>\n    <li><strong>Saved resources</strong> &mdash; Each time a student bookmarks or downloads a resource, the count is updated.</li>\n    <li><strong>Privacy</strong> &mdash; Individual events (which PDF was opened, what was searched) stay on the student's phone and are never sent to the Hub.</li>\n</ul>",
        "help.troubleshooting": "Troubleshooting",
        "help.troubleshooting_body": "<ul>\n    <li><strong>App cannot connect</strong> &mdash; Ensure your phone is on the EduMesh Wi-Fi and the Hub laptop is powered on. Restart the app and wait a few seconds.</li>\n    <li><strong>Forgot your password</strong> &mdash; Plug a keyboard into the Hub laptop and run <code>sudo ./reset_admin.sh</code> in a terminal. This resets the admin password to <code>lumina2026</code>.</li>\n    <li><strong>App is slow</strong> &mdash; Close other apps, restart EduMesh, or clear app data from Android Settings and reinstall.</li>\n    <li><strong>Hub storage is full</strong> &mdash; Delete unused resources from Content Manager. Check disk usage on the <span data-i18n=\"sidebar.home\">Home</span> page. For advanced cleanup, run <code>sudo ./setup_hub.sh</code>.</li>\n</ul>",
        "index.page_title": "Lumina Hub | Dashboard",
        "index.server_version": "Lumina Hub v1.0",
        "index.unit_gb": "GB",
        "index.unit_hours_short": "h",
        "index.unit_minutes_short": "m",
        "index.unit_percent": "%",
        "index.unit_seconds_short": "s",
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
        "settings.username_label": "Username:",
        "settings_language_description": "Choose your preferred language for the dashboard.",
        "settings_language_title": "Language",
        "sidebar.content": "Content Manager",
        "sidebar.danger": "Danger Zone",
        "sidebar.dark_mode": "Dark Mode",
        "sidebar.help": "Teacher Guide",
        "sidebar.home": "Home",
        "sidebar.lang_search_placeholder": "Search languages...",
        "sidebar.light_mode": "Light Mode",
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
        "students.hours_ago": "{n}h ago",
        "students.just_now": "Just now",
        "students.minutes_ago": "{n}m ago",
        "students.never": "Never",
        "students.page_title": "Students - Lumina Hub",
        "students.search": "Search by name or ID…",
        "students.subtitle": "View and manage registered students.",
        "students.title": "Students",
        "students.yesterday": "Yesterday",
        "students_connection_error": "Connection error. Check that the hub server is running.",
        "students_days_abbr": "d",
        "students_failed_load": "Failed to load students.",
        "students_hours_abbr": "h",
        "students_last_updated": "Last updated",
        "students_loading": "Loading students…",
        "students_none_registered": "No students registered yet. Students will appear here once they register through the app.",
        "students_refresh": "Refresh",
        "students_search_label": "Search",
        "students_unknown": "Unknown",
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
        "welcome.battery_unknown": "Unknown",
        "welcome.connection_error": "Connection error. Please check your network connection.",
        "welcome.display_name_error": "Please enter a name or skip.",
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
        "welcome.guide.for_teachers_body": "Teachers can log in above using their credentials. Once logged in, you can <strong>upload resources</strong>, <strong>view student analytics</strong>, <strong>manage grades and subjects</strong>, and <strong>configure the hub</strong> — including changing passwords and managing storage. Visit the <strong>Teacher Guide</strong> in the sidebar after logging in for detailed instructions.",
        "welcome.guide.getting_started_body": "<li><strong>Connect to Wi-Fi</strong> — Turn on your phone’s Wi-Fi and join the network named <strong>EduMesh</strong>. No password needed.</li><li><strong>Open the welcome page</strong> — Once connected, a login screen should appear automatically (captive portal). If not, open your browser and go to <strong>http://lumina.hub:8000</strong>.</li><li><strong>Download the app</strong> — Tap the <strong>Download App</strong> button in the top-right corner of this page to get the EduMesh APK.</li><li><strong>Install the app</strong> — Open the downloaded file and tap Install. If your phone asks, allow “Install from Unknown Sources” in Settings.</li><li><strong>Register</strong> — Open the EduMesh app, enter your name, and you’re in. You’ll be assigned a permanent student ID.</li><li><strong>Start learning</strong> — Browse textbooks, videos, past papers, and more. Tap any resource to view it, or download it to access offline.</li>",
        "welcome.guide.tracking_privacy_body": "<p style=\"font-size:0.875rem;color:var(--text-secondary);line-height:1.7;\">The app tracks your <strong>study time</strong> using a built-in timer and counts your <strong>daily streak</strong> of consecutive study days. This helps teachers see how the class is engaging with materials.</p><p style=\"font-size:0.875rem;color:var(--text-secondary);line-height:1.7;margin-top:0.5rem;\"><strong>Your privacy matters.</strong> Individual details — like which PDF you opened or what you searched for — stay on your phone and are <strong>never sent</strong> to the Hub. Only your total weekly minutes, streak days, and resource count are shared.</p>",
        "welcome.guide.troubleshooting_body": "<li><strong>Can’t connect to Wi-Fi?</strong> Make sure the Hub laptop is powered on and broadcasting. Ask your teacher to check.</li><li><strong>Captive portal not opening?</strong> Open your browser and manually go to <strong>http://lumina.hub:8000</strong>.</li><li><strong>App won’t install?</strong> Go to Settings > Security and enable “Install from Unknown Sources”. Then try again.</li><li><strong>App is slow or crashing?</strong> Close other apps, restart EduMesh, or clear app data from Android Settings and reinstall.</li>",
        "welcome.guide.using_app_body": "<p style=\"font-size:0.875rem;color:var(--text-secondary);line-height:1.7;margin-bottom:0.75rem;\">The EduMesh app has four tabs at the bottom:</p><ul style=\"font-size:0.875rem;color:var(--text-secondary);line-height:1.7;padding-left:1.25rem;\"><li><strong>Dashboard</strong> — See your study stats, recent activity, and quick-access resources.</li><li><strong>Browse</strong> — Explore all available resources by subject or grade. Search by keyword.</li><li><strong>Saved</strong> — View resources you’ve bookmarked or downloaded for offline use.</li><li><strong>Profile</strong> — View your weekly study time, streak, and saved resource count.</li></ul>",
        "welcome.hero.subtitle": "Access textbooks, videos, and study materials from the local mesh — no internet required.",
        "welcome.hero.title": "Your Offline Learning Network",
        "welcome.hide_password": "Hide Password",
        "welcome.invalid_creds": "Invalid credentials. Please try again.",
        "welcome.lang_search_placeholder": "Search...",
        "welcome.page_title": "Lumina Hub | Welcome",
        "welcome.password": "Password",
        "welcome.show_password": "Show Password",
        "welcome.signin": "Sign In",
        "welcome.step1": "Tap <strong>Download App</strong> in the top-right corner.",
        "welcome.step2": "Install the EduMesh app on your phone.",
        "welcome.step3": "Open the app to browse and download all available resources.",
        "welcome.storage": "Storage",
        "welcome.storage.used": "{used} GB / {total} GB used",
        "welcome.storage.used_pct": "{pct}% used",
        "welcome.storage_error": "Error loading storage info",
        "welcome.system_error": "Error loading system info",
        "welcome.teacher_login": "Educator Access",
        "welcome.teacher_subtitle": "Manage resources and monitor the mesh network.",
        "welcome.teacher_title": "Teacher Login",
        "welcome.tracking_privacy": "Study Tracking &amp; Privacy",
        "welcome.troubleshooting": "Troubleshooting",
        "welcome.unavailable": "Unavailable",
        "welcome.username": "Username",
        "welcome.using_app": "Using the App",
        "welcome.vitals": "Hub Vitals",
        "welcome.what_is": "What is Lumina Hub?",
        "welcome.what_is_body": "Lumina Hub is a local mesh server that delivers educational resources — textbooks, lecture videos, and past papers — directly to your device without using cellular data or internet.",
        "welcome_loading": "Loading…"
    },
};

/**
 * Store the encryption key on successful login.
 * @param {string} key - The encryption key from the login response
 */
function setEncryptionKey(key) {
    if (key) sessionStorage.setItem('lumina_encryption_key', key);
}

/**
 * Wrapper around fetch() for dashboard API calls.
 *
 * Error handling: Non-OK responses are NOT automatically rejected — callers must
 * check `res.ok`. This allows each page to handle 401, 403, and 500 differently.
 * Rate limiting: The server applies RateLimitMiddleware (20 requests/min per IP).
 * If rate-limited, the server returns 429; the caller should show a user-friendly
 * message and retry after a delay.
 * Demo mode: Not applicable — IS_DEMO has been removed from the codebase.
 *
 * @param {string} url - The URL to fetch
 * @param {Object} [options] - Standard fetch options (method, body, headers, etc.)
 * @returns {Promise<Response>} A Response object
 */
async function apiFetch(url, options = {}) {
    return fetch(url, options);
}

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
        const res = await fetch('/static/lang/' + code + '.json');
        if (res.ok) {
            const data = await res.json();
            if (!TRANSLATIONS[code]) TRANSLATIONS[code] = {};
            for (const key in data) {
                TRANSLATIONS[code][key] = data[key];
            }
        }
    } catch (e) {
        // File not found — use defaults
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
    wrap.style.cssText = 'position:fixed;top:0.75rem;right:3.5rem;z-index:500;';
    const style = document.createElement('style');
    style.textContent = '.lang-option:hover{background:var(--outline)!important}.lang-option.active-lang,.lang-option.active-lang:hover{background:var(--teal)!important;color:#fff!important}';
    document.head.appendChild(style);

    const btn = document.createElement('button');
    btn.id = 'langPickerBtn';
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
    overlay.style.cssText = 'display:none;position:fixed;inset:0;z-index:999;';
    overlay.addEventListener('click', closeLangPicker);
    document.body.appendChild(overlay);

    const dd = document.createElement('div');
    dd.id = 'langDropdown';
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
        return '<div class="lang-option' + (active ? ' active-lang' : '') + '" data-code="' + l.code + '" style="padding:0.5rem 0.75rem;cursor:pointer;font-size:0.85rem;display:flex;justify-content:space-between;align-items:center;border-radius:6px;"><span>' + esc(l.native) + '</span><span style="font-size:0.7rem;opacity:0.6;">' + esc(l.name) + '</span></div>';
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
    if (cached) {
        loggedInUser = cached;
        const el = document.getElementById('userInfo');
        if (el) el.innerHTML = '<div style="font-weight: 800; font-size: 1rem; color: #fff; letter-spacing: -0.015em;">' + esc(cached) + '</div>';
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
        const res = await apiFetch('/whoami');
        if (!res.ok) {
            window.location.href = '/static/error?reason=session_expired';
            return;
        }
        const data = await res.json();
        loggedInUser = data.username;
        userRole = data.role;
        sessionStorage.setItem('lumina-user', data.username);
        const userInfo = document.getElementById('userInfo');
        if (userInfo) {
            userInfo.innerHTML = '<div style="font-weight: 800; font-size: 1rem; color: #fff; letter-spacing: -0.015em;">' + esc(loggedInUser) + '</div>';
        }
    } catch (e) {
        console.error('Error loading whoami info', e);
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
function setActiveNav(navId) {
    document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
    document.querySelectorAll('.bottom-nav-item').forEach(el => el.classList.remove('active'));
    const nav = document.getElementById(navId);
    if (nav) nav.classList.add('active');
    const bottomNav = document.getElementById('bottom-' + navId);
    if (bottomNav) bottomNav.classList.add('active');
}

/**
 * Auto-detects the current page from location.pathname and highlights the correct
 * sidebar nav item and bottom-nav item. Runs once on DOMContentLoaded.
 * Path-to-key mapping covers all static dashboard pages.
 */
function initNav() {
    const path = location.pathname.replace(/\/+$/, '');
    const mapping = {
        '/static/index': 'home',
        '/static/manage-content': 'content',
        '/static/manage-security': 'security',
        '/static/students': 'students',
        '/static/student-detail': 'students',
        '/static/manage-help': 'help',
        '/static/manage-danger': 'danger',
        '/static/manage-settings': 'settings',
    };
    const key = mapping[path] || '';
    if (key) {
        document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
        document.querySelectorAll('.bottom-nav-item').forEach(el => el.classList.remove('active'));
        const navEl = document.getElementById('nav-' + key);
        if (navEl) navEl.classList.add('active');
        const bottomEl = document.getElementById('bottom-nav-' + key);
        if (bottomEl) bottomEl.classList.add('active');
    }
}

/**
 * Saves the current page scroll position to sessionStorage before navigating away.
 * Keyed by the current pathname so it can be restored on return.
 */
function saveScrollPosition() {
    try {
        sessionStorage.setItem('scroll:' + location.pathname, window.scrollY.toString());
    } catch(e) { /* sessionStorage may be unavailable */ }
}

/**
 * Restores the saved scroll position for the current page on load.
 * Uses a short timeout to let the DOM paint before scrolling.
 */
function restoreScrollPosition() {
    try {
        const saved = sessionStorage.getItem('scroll:' + location.pathname);
        if (saved !== null) {
            const pos = parseInt(saved, 10);
            if (pos > 0) {
                setTimeout(function() { window.scrollTo(0, pos); }, 10);
            }
        }
    } catch(e) { /* ignore */ }
}

/**
 * Hides/shows the mobile header on scroll.
 * Adds .hidden-header class when scrolling down past 50px, removes on scroll up.
 */
function initMobileHeaderScroll() {
    let lastScroll = 0;
    const header = document.querySelector('.mobile-header');
    if (!header) return;
    window.addEventListener('scroll', function() {
        const current = window.pageYOffset || document.documentElement.scrollTop;
        if (current > lastScroll && current > 50) {
            header.classList.add('hidden-header');
        } else {
            header.classList.remove('hidden-header');
        }
        lastScroll = current;
    }, { passive: true });
}

document.addEventListener('DOMContentLoaded', function() {
    initNav();
    if (!document.getElementById('welcomeLangBtn') && !document.querySelector('.lang-nav-wrap')) {
        initLangPicker();
    }
    loadTranslations(currentLang);
    initMobileHeaderScroll();
    try { history.scrollRestoration = 'manual'; } catch(e) { /* ignore */ }
    restoreScrollPosition();
    // Save scroll position before navigating to another dashboard page
    document.addEventListener('click', function(e) {
        const link = e.target.closest('a.bottom-nav-item, a.nav-item');
        if (link && link.href && link.href.indexOf(location.hostname) !== -1) {
            saveScrollPosition();
        }
    });

});
