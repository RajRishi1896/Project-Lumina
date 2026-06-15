# i18n Translation Debt Tracker

Tracks every key present in English source (`app_en.arb`, `en.json`) that is either **missing** or **falls back to English** in a non-English localization file.

---

## ARB Files (Flutter app)

### app_hi.arb — Hindi

| Key | Status | Notes |
|-----|--------|-------|
| semanticsSettings | Recently added (15 Jun 2026) | Needs native review |
| semanticsSearchResources | Recently added (15 Jun 2026) | Needs native review |
| semanticsFilterResources | Recently added (15 Jun 2026) | Needs native review |
| semanticsSelectLanguage | Recently added (15 Jun 2026) | Needs native review, contains {label} placeholder |
| semanticsOpenVideoPlayer | Recently added (15 Jun 2026) | Needs native review |
| semanticsCloseMiniPlayer | Recently added (15 Jun 2026) | Needs native review |
| semanticsTogglePlay | Recently added (15 Jun 2026) | Needs native review |
| tooltipBackToResource | Recently added (15 Jun 2026) | Needs native review |
| tooltipDeleteDownload | Recently added (15 Jun 2026) | Needs native review, contains {title} placeholder |
| connectionOfflineBanner | Recently added (15 Jun 2026) | Needs native review |
| notificationDownloadFailedTitle | Recently added (15 Jun 2026) | Needs native review |
| notificationDownloadFailedBody | Recently added (15 Jun 2026) | Needs native review, contains {title} placeholder |
| studentNameUnknown | Recently added (15 Jun 2026) | Needs native review |
| activityPastTense | Recently added (15 Jun 2026) | Needs native review, ICU-compatible fallback |
| storageAppSize | Recently added (15 Jun 2026) | Needs native review, contains {size} placeholder |
| hubStrengthCalculating | Recently added (15 Jun 2026) | Needs native review |

**Total: 16 keys** (all recently added, pending native review)

### app_kn.arb — Kannada

Same 16 keys as above — all recently added, pending native review.

**Total: 16 keys**

### app_fr.arb — French

Same 16 keys as above — all recently added, pending native review.

**Total: 16 keys**

---

## JSON Files (Web server)

### hi.json — Hindi

Approximately **290+ keys** fall back to English. Key groups:

| Group | Estimated keys | Example untranslated keys |
|-------|---------------|--------------------------|
| `content.add_subject_*` | 8 | `content.add_subject_button`, `content.add_subject_label_class`, `content.add_subject_title` |
| `content.library_*` | 10 | `content.library_empty`, `content.library_title`, `content.library_th_action` |
| `content.manage_subjects_*` | 8 | `content.manage_subjects_empty`, `content.manage_subjects_title` |
| `content.modal_*` | 20 | `content.modal_confirm`, `content.modal_delete_permanently`, `content.modal_password_requirement` |
| `content.page_*` | 2 | `content.page_description`, `content.page_title` |
| `content.upload_*` | 13 | `content.upload_button`, `content.upload_label_category`, `content.upload_title` |
| `danger.*` | ~100 | Most of the `danger.*` namespace, including all confirm dialogs, error messages, table labels |
| `security.*` | ~48 | `security.account_settings` through `security.update_and_continue` |
| `settings.*` | ~60 | Most `settings.*` keys including confirm bodies, error messages, modal content |
| `student_detail.*` | ~10 | `student_detail.active_days`, `student_detail.downloaded_label`, etc. |
| `students.*` (time) | ~6 | `students.days_ago`, `students.hours_ago`, `students.just_now`, etc. |
| `welcome.*` (misc) | ~6 | `welcome.page_title`, `welcome.show_password`, `welcome.lang_search_placeholder` |

**Total: ~290+ keys** (bulk of admin/teacher-facing strings in English)

### kn.json — Kannada

Same ~290+ key groups as hi.json — identical set of English fallbacks.

**Total: ~290+ keys**

### fr.json — French

Same ~290+ key groups. However, more individual keys within each group are translated compared to hi/kn.

**Total: ~250+ keys**

---

## Summary

| Language | ARB debt | JSON debt | Total |
|----------|----------|-----------|-------|
| Hindi (hi) | 16 | ~290 | ~306 |
| Kannada (kn) | 16 | ~290 | ~306 |
| French (fr) | 16 | ~250 | ~266 |
| **Combined** | **48** | **~830** | **~878** |

Key groups requiring immediate native speaker review (student-facing):
1. `welcome.*` namespace (onboarding flow)
2. `error_*` strings (error pages, captive portal)
3. `student_detail.*` namespace (student analytics)

Key groups with lower priority (admin-facing):
- `danger.*`, `security.*`, `settings.*`, `content.*` — used by teachers/admins only

---

## Remediation Plan

1. Batch-translate all JSON keys using automated pipeline (Gemini/Ollama)
2. Flag all machine-translated keys with `x_machine_translated: true` in ARB metadata
3. Native speaker review for student-facing keys before next release
4. Remove `x_machine_translated` flags after review is complete
