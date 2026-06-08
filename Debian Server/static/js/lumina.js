/* ── Shared Lumina Dashboard JS ────────────────────────────────────────── */

/* ── Helpers ─────────────────────────────────────────────────────────────── */

/**
 * Whether the page is opened directly from the filesystem (file:// protocol).
 * When true, all API calls are skipped and demo data is used instead.
 */
const IS_DEMO = window.location.protocol === 'file:';

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
        "app.title": "Lumina Hub",
        "app.tagline": "Your Offline Learning Network",
        "sidebar.home": "Home",
        "sidebar.content": "Content Manager",
        "sidebar.security": "Security",
        "sidebar.students": "Students",
        "sidebar.help": "Help",
        "sidebar.danger": "Danger Zone",
        "sidebar.settings": "Settings",
        "sidebar.logout": "Log out",
        "sidebar.dark_mode": "Dark Mode",
        "nav.download": "Download App",
        "teacher.help.header": "Need help?",
        "teacher.help.body": "View setup guides, troubleshooting tips, and admin instructions.",
        "settings_language_title": "Language",
        "settings_language_description": "Choose your preferred language for the dashboard.",
    },
};

// ── AES-256-GCM encryption for API payloads ──────────────────────────

/** Look up the AES-256-GCM key for the current session from sessionStorage */
function getEncryptionKey() {
    return sessionStorage.getItem('lumina_encryption_key');
}

/** Store the encryption key on successful login */
function setEncryptionKey(key) {
    if (key) sessionStorage.setItem('lumina_encryption_key', key);
}

/** Clear encryption key on logout */
function clearEncryptionKey() {
    sessionStorage.removeItem('lumina_encryption_key');
}

/**
 * Encrypt a JSON-serializable object using AES-256-GCM via Web Crypto API.
 * Returns {"encrypted": "<base64>"} wrapper.
 */
async function encryptPayload(data, keyBase64) {
    const keyBytes = base64ToBytes(keyBase64);
    const plaintext = new TextEncoder().encode(JSON.stringify(data));
    
    const key = await crypto.subtle.importKey(
        'raw', keyBytes, { name: 'AES-GCM' }, false, ['encrypt']
    );
    const nonce = crypto.getRandomValues(new Uint8Array(12));
    const encrypted = await crypto.subtle.encrypt(
        { name: 'AES-GCM', iv: nonce }, key, plaintext
    );
    const combined = new Uint8Array(12 + encrypted.byteLength);
    combined.set(nonce, 0);
    combined.set(new Uint8Array(encrypted), 12);
    return { encrypted: bytesToBase64(combined) };
}

/**
 * Decrypt a {"encrypted": "<base64>"} wrapper and return the parsed JSON object.
 */
async function decryptResponse(wrapper, keyBase64) {
    const keyBytes = base64ToBytes(keyBase64);
    const raw = base64ToBytes(wrapper.encrypted);
    const nonce = raw.slice(0, 12);
    const ciphertext = raw.slice(12);
    
    const key = await crypto.subtle.importKey(
        'raw', keyBytes, { name: 'AES-GCM' }, false, ['decrypt']
    );
    const decrypted = await crypto.subtle.decrypt(
        { name: 'AES-GCM', iv: nonce }, key, ciphertext
    );
    return JSON.parse(new TextDecoder().decode(decrypted));
}

// Base64 helpers (IE-safe, uses built-in btoa/atob with UTF-8 handling)

/**
 * Convert a Uint8Array to a base64-encoded string.
 * @param {Uint8Array} bytes - Binary data to encode
 * @returns {string} Base64-encoded string
 */
function bytesToBase64(bytes) {
    let binary = '';
    for (let i = 0; i < bytes.length; i++) {
        binary += String.fromCharCode(bytes[i]);
    }
    return btoa(binary);
}

/**
 * Decode a base64-encoded string to a Uint8Array.
 * @param {string} str - Base64-encoded string
 * @returns {Uint8Array} Decoded binary data
 */
function base64ToBytes(str) {
    const binary = atob(str);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
}

/**
 * Wrapper around fetch() that encrypts request bodies and decrypts responses.
 *
 * ## Encryption flow
 * For POST/PUT requests with a body, the JSON body is encrypted with AES-256-GCM
 * using the session key obtained at login. Responses containing `{"encrypted": "..."}`
 * are automatically decrypted. Falls back to plain JSON if no encryption key is
 * available (backwards compatibility with unencrypted endpoints).
 *
 * ## Error handling
 * Encryption/decryption failures are non-fatal: the request is sent as plaintext
 * and the response is returned as-is. Warnings are logged to console.
 *
 * @param {string} url - The URL to fetch
 * @param {Object} [options] - Standard fetch options (method, body, headers, etc.)
 * @returns {Promise<Response>} A Response-like object (decrypted if applicable)
 */
async function apiFetch(url, options = {}) {
    const encKey = getEncryptionKey();
    
    // Encrypt request body if we have a key (skip FormData — can't be JSON-serialized)
    if (encKey && options.body && (options.method === 'POST' || options.method === 'PUT' || !options.method) && !(options.body instanceof FormData)) {
        try {
            const bodyData = typeof options.body === 'string' ? JSON.parse(options.body) : options.body;
            const encrypted = await encryptPayload(bodyData, encKey);
            options.body = JSON.stringify(encrypted);
        } catch (e) {
            console.warn('Encryption failed, sending plaintext:', e);
        }
    }
    
    const response = await fetch(url, options);
    
    // Try to decrypt response
    if (encKey) {
        try {
            const text = await response.text();
            if (text) {
                const parsed = JSON.parse(text);
                if (parsed && parsed.encrypted) {
                    const decrypted = await decryptResponse(parsed, encKey);
                    const newResponse = {
                        ok: response.ok,
                        status: response.status,
                        statusText: response.statusText,
                        headers: response.headers,
                        json: async () => decrypted,
                        text: async () => JSON.stringify(decrypted),
                    };
                    return newResponse;
                }
                const newResponse = {
                    ok: response.ok,
                    status: response.status,
                    statusText: response.statusText,
                    headers: response.headers,
                    json: async () => parsed,
                    text: async () => text,
                };
                return newResponse;
            }
        } catch (e) {
            console.warn('Response decryption failed:', e);
        }
    }
    
    return response;
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
    if (lang && lang[key]) {
        var val = lang[key];
    } else if (TRANSLATIONS.en && TRANSLATIONS.en[key]) {
        var val = TRANSLATIONS.en[key];
    } else {
        return key;
    }
    if (params) {
        for (var k in params) {
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
 */
async function loadTranslations(code) {
    try {
        const res = await fetch('/static/lang/' + code + '.json');
        if (res.ok) {
            const data = await res.json();
            if (!TRANSLATIONS[code]) TRANSLATIONS[code] = {};
            for (var key in data) {
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
        var key = el.getAttribute('data-i18n');
        var translated = __(key);
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
    var label = document.getElementById('langPickerLabel');
    if (label) {
        var langObj = LANGUAGES.find(function(l){ return l.code === currentLang; });
        if (langObj) label.textContent = langObj.native;
    }
}

/**
 * Switch the active language. Loads remote translations if not yet cached.
 * @param {string} code - Language code ('en', 'hi', 'kn', etc.)
 */
async function setLanguage(code) {
    if (code === currentLang) return;
    currentLang = code;
    localStorage.setItem('lumina-lang', code);
    if (!TRANSLATIONS[code]) {
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
    var existing = document.getElementById('langPickerWrap');
    if (existing) return;

    var wrap = document.createElement('div');
    wrap.id = 'langPickerWrap';
    wrap.style.cssText = 'position:fixed;top:0.75rem;right:3.5rem;z-index:500;';

    var btn = document.createElement('button');
    btn.id = 'langPickerBtn';
    btn.style.cssText = 'height:36px;border-radius:18px;border:1px solid var(--outline);background:var(--bg-surface);color:var(--text-primary);cursor:pointer;display:flex;align-items:center;gap:0.4rem;padding:0 0.75rem;box-shadow:0 1px 3px rgba(0,0,0,0.08);font-family:inherit;font-size:0.8rem;font-weight:700;transition:all 0.2s;';
    var initialLang = LANGUAGES.find(function(l){ return l.code === currentLang; }) || LANGUAGES[0];
    btn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width:16px;height:16px;flex-shrink:0;"><circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg><span id="langPickerLabel">' + esc(initialLang.native) + '</span>';
    btn.onmouseenter = function(){ btn.style.background = 'var(--outline)'; };
    btn.onmouseleave = function(){ btn.style.background = 'var(--bg-surface)'; };
    btn.onclick = function(e) { e.stopPropagation(); toggleLangPicker(); };

    wrap.appendChild(btn);
    document.body.appendChild(wrap);

    var overlay = document.createElement('div');
    overlay.id = 'langOverlay';
    overlay.style.cssText = 'display:none;position:fixed;inset:0;z-index:999;';
    overlay.onclick = closeLangPicker;
    document.body.appendChild(overlay);

    var dd = document.createElement('div');
    dd.id = 'langDropdown';
    dd.style.cssText = 'display:none;position:fixed;top:3.75rem;right:1rem;width:220px;background:var(--bg-surface);border:1px solid var(--outline);border-radius:10px;box-shadow:0 8px 24px rgba(0,0,0,0.2);z-index:1000;overflow:hidden;';
    dd.innerHTML = '<div style="padding:0.5rem;border-bottom:1px solid var(--outline);"><input id="langSearch" type="text" placeholder="Search languages..." style="width:100%;padding:0.4rem 0.6rem;font-size:0.8rem;font-family:inherit;border:1px solid var(--outline);border-radius:6px;background:var(--bg-surface);color:var(--text-primary);outline:none;box-sizing:border-box;"></div><div id="langList" style="overflow-y:auto;max-height:220px;"></div>';
    document.body.appendChild(dd);

    renderLangList('');

    document.getElementById('langSearch').addEventListener('input', function() {
        renderLangList(this.value.toLowerCase());
    });
}

/**
 * Render the language list inside the dropdown, filtered by search query.
 * Highlights the active language with teal background.
 * @param {string} query - Lowercased search filter string
 */
function renderLangList(query) {
    var list = document.getElementById('langList');
    if (!list) return;
    var filtered = query ? LANGUAGES.filter(function(l){ return l.name.toLowerCase().indexOf(query) !== -1 || l.native.indexOf(query) !== -1 || l.code.indexOf(query) !== -1; }) : LANGUAGES;
    list.innerHTML = filtered.map(function(l) {
        var active = l.code === currentLang;
        var bg = active ? 'var(--teal)' : 'transparent';
        var clr = active ? '#fff' : '';
        return '<div class="lang-option" data-code="' + l.code + '" style="padding:0.5rem 0.75rem;cursor:pointer;font-size:0.85rem;display:flex;justify-content:space-between;align-items:center;border-radius:6px;' + (active ? 'background:' + bg + ';color:' + clr + ';' : '') + '" onmouseenter="this.style.background=\'' + (active ? 'var(--teal)' : 'var(--outline)') + '\';this.style.color=\'' + (active ? '#fff' : '') + '\'" onmouseleave="this.style.background=\'' + (active ? 'var(--teal)' : 'transparent') + '\';this.style.color=\'' + (active ? '#fff' : '') + '\'" onclick="setLanguage(\'' + l.code + '\')"><span>' + esc(l.native) + '</span><span style="font-size:0.7rem;opacity:0.6;">' + esc(l.name) + '</span></div>';
    }).join('');
}

/**
 * Toggle the language picker dropdown open/closed.
 * Shows/hides the dropdown and its backing overlay.
 */
function toggleLangPicker() {
    var dd = document.getElementById('langDropdown');
    try { dd.style.display = dd.style.display === 'block' ? 'none' : 'block'; } catch(e){ return; }
    var ov = document.getElementById('langOverlay');
    if (ov) ov.style.display = dd.style.display;
    if (dd.style.display === 'block') {
        renderLangList('');
        setTimeout(function() { var s = document.getElementById('langSearch'); if(s) s.focus(); }, 50);
    }
}

/** Close the language picker dropdown and overlay. */
function closeLangPicker() {
    var dd = document.getElementById('langDropdown');
    var ov = document.getElementById('langOverlay');
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
    if (label) label.textContent = theme === 'dark' ? 'Light Mode' : 'Dark Mode';
}

/** Toggle between light and dark themes based on current preference. */
function toggleTheme() { setTheme(getPreferredTheme() === 'dark' ? 'light' : 'dark'); }

/* ── Notifications ───────────────────────────────────────────────────────── */

/**
 * Show a temporary toast notification at the bottom of the page.
 * Toast auto-dismisses after 3 seconds with a fade-out animation.
 * @param {string} msg - Message text to display
 * @param {boolean} isError - If true, uses danger/red background; otherwise success/green
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
 */
async function loadWhoAmI() {
    try {
        if (IS_DEMO) {
            loggedInUser = 'admin';
            userRole = 'admin';
        } else {
            const res = await apiFetch('/whoami');
            if (!res.ok) {
                window.location.href = '/static/error?reason=session_expired';
                return;
            }
            const data = await res.json();
            loggedInUser = data.username;
            userRole = data.role;
            sessionStorage.setItem('lumina-user', data.username);
        }
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
 */
function setActiveNav(navId) {
    document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
    document.querySelectorAll('.bottom-nav-item').forEach(el => el.classList.remove('active'));
    const nav = document.getElementById(navId);
    if (nav) nav.classList.add('active');
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

document.addEventListener('DOMContentLoaded', function() {
    initNav();
    initLangPicker();
    loadTranslations(currentLang);
    // Clear encryption key on logout
    document.querySelectorAll('a[href="/logout"]').forEach(function(el) {
        el.addEventListener('click', clearEncryptionKey);
    });
});
