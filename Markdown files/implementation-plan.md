# Implementation Plan

## Goal
Fix the highest-risk audit findings first: async/blocking server paths, user-visible Flutter correctness issues, then structural and policy debt.

## Execution Order

### 1. Server prune path and file I/O
Primary risks:
- [Debian Server/app/api.py](../Debian%20Server/app/api.py#L51) runs raw `sqlite3.connect()` inside the hourly prune coroutine and swallows failures.
- [Debian Server/app/routers/resources.py](../Debian%20Server/app/routers/resources.py#L233) and [Debian Server/app/routers/resources.py](../Debian%20Server/app/routers/resources.py#L304) write upload files synchronously in request handlers.
- [Debian Server/app/routers/media.py](../Debian%20Server/app/routers/media.py#L52) opens streamed files synchronously.

Planned fix:
- Move the prune query block into a worker-thread helper or replace it with the async DB wrapper used elsewhere.
- Wrap upload writes and file reads in `asyncio.to_thread` helpers so request handlers do not block the event loop.
- Keep the existing file naming and validation logic unchanged.

Validation:
- Start the server with `python main.py`.
- Exercise upload, stream, and prune code paths if available.
- Confirm no new warnings or errors in the touched files.

### 2. Profile setup correctness
Primary risks:
- [EduMesh-Android/lib/features/auth/presentation/profile_setup_page.dart](../EduMesh-Android/lib/features/auth/presentation/profile_setup_page.dart#L43) can continue with an empty grade when grade loading fails.
- [EduMesh-Android/lib/features/auth/presentation/profile_setup_page.dart](../EduMesh-Android/lib/features/auth/presentation/profile_setup_page.dart#L52) fires the profile update queue without surfacing failure.

Planned fix:
- Block save when no valid grade is available.
- Show a localized error or retry state when grade loading fails.
- Await or otherwise observe the mutation enqueue result before navigating away.

Validation:
- Run `dart analyze lib/`.
- Reproduce the profile setup flow with the hub unavailable and with `/grades` failing.

### 3. Kiwix/WebView error handling
Primary risk:
- [EduMesh-Android/lib/features/dashboard/presentation/kiwix_view.dart](../EduMesh-Android/lib/features/dashboard/presentation/kiwix_view.dart#L46) only logs WebView load errors.

Planned fix:
- Clear `_isLoading` on resource error.
- Surface a recoverable error state or retry action instead of leaving the page stuck.

Validation:
- Run `dart analyze lib/`.
- Load a broken URL or invalid HTML source and confirm the view recovers.

### 4. Theme and spacing policy debt
Primary risks:
- [EduMesh-Android/lib/core/theme/lumina_lite_theme.dart](../EduMesh-Android/lib/core/theme/lumina_lite_theme.dart#L7) contains many hardcoded `Color(0xFF...)` values.
- [EduMesh-Android/lib/core/theme/lumina_lite_theme.dart](../EduMesh-Android/lib/core/theme/lumina_lite_theme.dart#L73) and [EduMesh-Android/lib/core/theme/lumina_lite_theme.dart](../EduMesh-Android/lib/core/theme/lumina_lite_theme.dart#L168) use raw spacing literals.
- [EduMesh-Android/lib/shared/widgets/pdf_viewer_page.dart](../EduMesh-Android/lib/shared/widgets/pdf_viewer_page.dart#L155), [EduMesh-Android/lib/shared/widgets/pdf_viewer_page.dart](../EduMesh-Android/lib/shared/widgets/pdf_viewer_page.dart#L162), [EduMesh-Android/lib/shared/widgets/pdf_viewer_page.dart](../EduMesh-Android/lib/shared/widgets/pdf_viewer_page.dart#L163), and [EduMesh-Android/lib/shared/widgets/pdf_viewer_page.dart](../EduMesh-Android/lib/shared/widgets/pdf_viewer_page.dart#L249) violate the spacing rules.

Planned fix:
- Replace theme literals with `LuminaColors` or `ColorScheme` tokens where possible.
- Replace raw spacing values with `AppSpacing` constants and responsive `.h` / `.w` usage.
- Avoid changing visual intent while doing the cleanup.

Validation:
- Run `dart analyze lib/`.
- Spot-check the affected screens for visual regressions.

### 5. Web i18n fallback
Primary risk:
- [Debian Server/static/js/lumina.js](../Debian%20Server/static/js/lumina.js#L34) and [Debian Server/static/js/lumina.js](../Debian%20Server/static/js/lumina.js#L57) depend on `TRANSLATIONS.en` fallback lookups.

Planned fix:
- Confirm the English fallback table contains all keys in `static/lang/en.json`.
- If keys are missing, seed `TRANSLATIONS.en` from the full JSON payload or another reliable local source.
- Keep the `loadTranslations(currentLang)` boot path intact.

Validation:
- Compare key sets across `static/lang/en.json`, `hi.json`, `kn.json`, and `fr.json`.
- Load the dashboard pages in the browser and confirm missing-key fallback does not surface raw keys.

## Acceptance Criteria
- Server startup succeeds.
- `dart analyze lib/` succeeds.
- The affected Flutter flows no longer fail silently.
- No new blocking I/O remains in async request paths touched by this plan.
- No new localization regressions are introduced.

## Recommended Commit Sequencing
1. Server prune/file-I/O fixes.
2. Profile setup correctness.
3. Kiwix/WebView error handling.
4. Theme and spacing cleanup.
5. Web i18n fallback repair.
6. Completed. Deferred cleanup is intentionally excluded.

## Notes
- This plan intentionally defers structural cleanup until the runtime issues are removed.
- The audit did not confirm some broader pattern matches as real defects, so they are not included here.
- The resources router split is intentionally out of scope for this pass.