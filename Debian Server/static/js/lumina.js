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
    "content.notif.subject_deleted": "Subject \"{name}\" deleted successfully.",
    "content.notif.subject_delete_failed": "Could not delete subject.",
    "content.notif.pwd_fields_required": "Please fill in both fields.",
    "content.notif.pwd_mismatch": "Passwords do not match.",
    "content.notif.pwd_updated": "Password updated successfully. Reloading...",
    "content.notif.pwd_update_failed": "Could not update password."
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
        const res = await fetch('/static/lang/' + code + '.json');
        if (res.ok) {
            const data = await res.json();
            if (!TRANSLATIONS[code]) TRANSLATIONS[code] = {};
            for (const key in data) {
                TRANSLATIONS[code][key] = data[key];
            }
        }
        // Always ensure English fallback is fully loaded from en.json
        const enRes = await fetch('/static/lang/en.json');
        if (enRes.ok) {
            const enData = await enRes.json();
            if (!TRANSLATIONS.en) TRANSLATIONS.en = {};
            for (const key in enData) {
                TRANSLATIONS.en[key] = enData[key];
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

/**
 * Render the logged-in user display in the sidebar.
 * Shared between the synchronous cached render and the async whoami fetch.
 * @param {string} username
 * @returns {void}
 */
function renderUserInfo(username) {
    const el = document.getElementById('userInfo');
    if (el) el.innerHTML = '<div style="font-weight: 800; font-size: 1rem; color: #fff; letter-spacing: -0.015em;">' + esc(username) + '</div>';
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
        renderUserInfo(cached);
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
        const res = await fetch('/whoami');
        if (!res.ok) {
            window.location.href = '/static/error?reason=session_expired';
            return;
        }
        const data = await res.json();
        loggedInUser = data.username;
        userRole = data.role;
        sessionStorage.setItem('lumina-user', data.username);
        renderUserInfo(data.username);
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
                let attempts = 0;
                (function tryScroll() {
                    // Wait until page content is tall enough or we've tried for ~1s
                    if (document.body.scrollHeight > pos || ++attempts > 10) {
                        window.scrollTo(0, pos);
                    } else {
                        setTimeout(tryScroll, 100);
                    }
                })();
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
