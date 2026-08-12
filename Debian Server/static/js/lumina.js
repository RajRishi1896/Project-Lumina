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
        var ctx = this, args = arguments;
        timer = setTimeout(function() { fn.apply(ctx, args); }, delay);
    };
}

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
    return new Date(iso).toLocaleDateString(currentLang);
}


/* ── i18n / Language ──────────────────────────────────────────────────────── */

/** @type {Array<{code:string, name:string, native:string}>} Available languages */
const LANGUAGES = [
    { code: 'en', name: 'English', native: 'English' },
    { code: 'hi', name: 'Hindi', native: 'हिन्दी' },
    { code: 'kn', name: 'Kannada', native: 'ಕನ್ನಡ' },
    { code: 'fr', name: 'French', native: 'Français' },
    { code: 'ta', name: 'Tamil', native: 'தமிழ்' },
    { code: 'te', name: 'Telugu', native: 'తెలుగు' },
];

/** @type {string} Current language code, persisted to localStorage */
let currentLang = localStorage.getItem('lumina-lang') || 'en';

/**
 * Translations are loaded from /static/lang/{code}.json into window._translations
 * (see loadTranslations). There is no inline fallback table -- a missing key
 * renders as the key name itself as a debug signal.
 */

/**
 * Look up a translated string for the current language.
 * Falls back to English (window._translations.en) if no translation exists.
 * @param {string} key - Dot-notation key (e.g. 'sidebar.home')
 * @param {Object} [params] - Optional interpolation values, using {name} syntax
 * @returns {string}
 */
function __(key, params) {
    const t = window._translations;
    let val = (t && t[currentLang] && t[currentLang][key]) || (t && t.en && t.en[key]) || key;
    if (params) {
        for (const k in params) {
            val = val.replace('{' + k + '}', params[k]);
        }
    }
    return val;
}

/**
 * Fetch translations from an external JSON file into window._translations.
 *
 * ## i18n source pattern
 * Called once on page load for the current language. English (en.json) is
 * ALWAYS fetched on every call so the fallback table is never stale -- do not
 * reintroduce an early return for 'en'. If a file is missing, lookups fall
 * back to English, then to the raw key name.
 *
 * @param {string} code - Language code to load
 * @returns {Promise<void>}
 */
async function loadTranslations(code) {
    if (window._translations && window._translations[code] && code !== 'en') { applyLanguage(); return; }
    const t = window._translations || (window._translations = {});
    try {
        const res = await fetch('/static/lang/' + code + '.json', { credentials: 'include' });
        if (res.ok) {
            t[code] = await res.json();
        }
        const enRes = await fetch('/static/lang/en.json', { credentials: 'include' });
        if (enRes.ok) {
            t.en = await enRes.json();
        }
    } catch (e) {
        // File not found -- key names are shown as-is
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
    if (!window._translations || !window._translations[code] || code === 'en') {
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
            modal.firstElementChild.style.border = '2px solid var(--teal)';
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
    document.body.classList.toggle('sidebar-open', sidebar && sidebar.classList.contains('open'));
}

/* ── Active nav highlighting ─────────────────────────────────────────────── */

/**
 * Renders the sidebar (<aside>) and bottom nav (#bottomNav) into their container
 * elements. Called once on DOMContentLoaded. Eliminates identical sidebar/nav
 * HTML that was duplicated across all 8 dashboard pages.
 */
function renderLayout() {
    if (document.getElementById('welcome-content')) return;
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

    // Determine active key
    var path = location.pathname.replace(/\/+$/, '');
    var mapping = { '/static/index':'home','/static/courses':'courses','/static/manage-content':'content','/static/manage-settings':'settings','/static/students':'students','/static/student-detail':'students','/static/manage-help':'help','/static/manage-danger':'danger' };
    var key = mapping[path] || '';

    // If sidebar already has nav items, just toggle active classes (no flash)
    var existingNav = aside.querySelector('nav');
    if (existingNav && existingNav.children.length > 0) {
        var idMap = { settings: 'account' };
        var allItems = aside.querySelectorAll('.nav-item');
        for (var i = 0; i < allItems.length; i++) {
            var itemId = allItems[i].id.replace('nav-', '');
            allItems[i].classList.toggle('active', itemId === (idMap[key] || key));
        }
        var allBtm = bottomNav.querySelectorAll('.bottom-nav-item');
        for (var j = 0; j < allBtm.length; j++) {
            var btmId = allBtm[j].id.replace('bottom-nav-', '');
            allBtm[j].classList.toggle('active', btmId === (idMap[key] || key));
        }
        return;
    }

    // First render: build full sidebar
    var cacheKey = (userRole || '') + ':' + key;
    renderLayout._last = cacheKey;
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
        '<button id="confirmCancelBtn" class="btn btn-outline" data-i18n="settings.confirm.cancel_btn" style="border-color: var(--outline); color: var(--on-surface); background: transparent; padding: 0.625rem 1.25rem;">Cancel</button>' +
        '<button id="confirmConfirmBtn" class="btn" data-i18n="settings.confirm.ok_btn" style="background: var(--danger); color: #fff; padding: 0.625rem 1.25rem;">Confirm</button></div></div>';

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
        '<h3 id="forceResetModalTitle" data-i18n="settings.modal.reset_title" style="font-size: 1.35rem; font-weight: 800; color: var(--on-surface); margin-top: 0; margin-bottom: 0.5rem;">Password Reset Required</h3>' +
        '<p data-i18n="settings.modal.reset_body" style="color: var(--on-surface); opacity: 0.7; font-size: 0.875rem; line-height: 1.5; margin-bottom: 1.5rem;">An administrator has forced a password reset on your account. You must change your password before you can proceed.</p>' +
        '<div id="forceResetNotif" style="display: none; padding: 0.75rem 1rem; margin-bottom: 1rem; border-radius: 6px; font-weight: 700; font-size: 0.85rem; text-align: center;"></div>' +
        '<div class="form-group" style="text-align: left; margin-bottom: 1rem;">' +
        '<label for="forceNewPwd" data-i18n="settings.modal.new_password_label" style="display: block; font-size: 0.75rem; font-weight: 700; color: var(--on-surface); opacity: 0.7; margin-bottom: 0.375rem;">New Password</label>' +
        '<div class="password-container"><input type="password" id="forceNewPwd" data-i18n-placeholder="settings.modal.new_password_placeholder" placeholder="Enter new password" style="width: 100%; padding: 0.65rem; padding-right: 2.5rem; border: 1px solid var(--outline); border-radius: 6px; background: var(--surface); color: var(--on-surface);">' +
        '<button type="button" class="pwd-toggle" data-target="forceNewPwd"><svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg></button></div>' +
        '<div data-i18n="settings.modal.password_hint" style="font-size:0.75rem;color:var(--text-muted);margin-top:0.375rem;">Must be 8+ chars, with uppercase, lowercase & a digit.</div></div>' +
        '<div class="form-group" style="text-align: left; margin-bottom: 1.5rem;">' +
        '<label for="forceConfirmPwd" data-i18n="settings.modal.confirm_password_label" style="display: block; font-size: 0.75rem; font-weight: 700; color: var(--on-surface); opacity: 0.7; margin-bottom: 0.375rem;">Confirm New Password</label>' +
        '<div class="password-container"><input type="password" id="forceConfirmPwd" data-i18n-placeholder="settings.modal.confirm_password_placeholder" placeholder="Confirm new password" style="width: 100%; padding: 0.65rem; padding-right: 2.5rem; border: 1px solid var(--outline); border-radius: 6px; background: var(--surface); color: var(--on-surface);">' +
        '<button type="button" class="pwd-toggle" data-target="forceConfirmPwd"><svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg></button></div></div>' +
        '<button id="btn-submitForcePasswordReset" class="btn btn-primary" data-i18n="settings.modal.update_btn" style="width: 100%; padding: 0.75rem; font-size: 0.875rem;">Update and Continue</button></div>';

    document.body.appendChild(confirmModal);
    document.body.appendChild(resetModal);

    // Delegated eye-toggle for password fields
    document.addEventListener('click', function(e) {
        var btn = e.target.closest('.pwd-toggle');
        if (!btn) return;
        var inp = document.getElementById(btn.dataset.target);
        if (!inp) return;
        var svg = btn.querySelector('svg');
        var eyeOpen = '<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/>';
        var eyeOff = '<path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/>';
        if (inp.type === 'password') {
            inp.type = 'text';
            svg.innerHTML = eyeOff;
        } else {
            inp.type = 'password';
            svg.innerHTML = eyeOpen;
        }
    });

    // Update modal text when language changes
    document.addEventListener('languageChanged', function() {
        var titleEl = document.getElementById('confirmModalTitle');
        var textEl = document.getElementById('confirmModalText');
        var cancelBtn = document.getElementById('confirmCancelBtn');
        var confirmBtn = document.getElementById('confirmConfirmBtn');
        if (cancelBtn) cancelBtn.textContent = __('settings.confirm.cancel_btn');
        if (confirmBtn) confirmBtn.textContent = __('settings.confirm.ok_btn');
        var resetTitle = document.getElementById('forceResetModalTitle');
        var resetBtn = document.getElementById('btn-submitForcePasswordReset');
        if (resetTitle) resetTitle.textContent = __('settings.modal.reset_title');
        if (resetBtn) resetBtn.textContent = __('settings.modal.update_btn');
    });
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
// Registry lives on window so pages' inline scripts (which run during parse,
// before this deferred file) can register their init functions on direct load.
const _pageInitRegistry = window._pageInitRegistry = window._pageInitRegistry || {};
const _pageCleanupFns = [];
let _isNavigating = false;

/**
 * Register a cleanup function called before SPA navigation.
 * Runs when navigateTo() replaces the current page; timers and listeners
 * registered by a page's init should be torn down here to avoid leaks.
 * @param {Function} fn - Cleanup function invoked before navigating away
 */
window.registerPageCleanup = function(fn) { _pageCleanupFns.push(fn); };

/**
 * Runs the current page's registered init function from _pageInitRegistry.
 * Called on DOMContentLoaded and after every SPA navigation. Pages register
 * in their inline script (they parse before this deferred file loads);
 * a missing registration logs an error instead of failing silently.
 */
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
        '/static/flashcards': 'flashcards',
    };
    const key = mapping[path];
    if (!key) return;
    if (!_pageInitRegistry[key]) {
        console.error('No page init registered for "' + key + '" (' + path + '). Page will not initialize.');
        return;
    }
    _pageInitRegistry[key]();
}

/**
 * SPA navigation: fetch the target page, swap #app-content, inject its inline
 * scripts, run registered cleanups, then re-init nav and translations without
 * a full page reload. Falls back to a plain location change on any failure.
 * @param {string} url - Absolute path to fetch (e.g. '/static/courses')
 * @param {boolean} [pushHistory=true] - Whether to push a history state entry
 * @returns {Promise<void>}
 */
async function navigateTo(url, pushHistory) {
    if (pushHistory === undefined) pushHistory = true;
    if (url === location.pathname) return;
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
        // Run registered page cleanup functions before evaluating new scripts
        _pageCleanupFns.forEach(function(fn) { try { fn(); } catch(e) {} });
        _pageCleanupFns.length = 0;
        // Register the fetched page's init: run its inline scripts natively via
        // script injection (no eval -- CSP-friendly, errors surface on their own
        // line instead of being swallowed by an empty catch).
        doc.querySelectorAll('script').forEach(function(script) {
            if (!script.src) {
                const el = document.createElement('script');
                el.textContent = script.textContent;
                document.body.appendChild(el);
                el.remove();
            }
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
