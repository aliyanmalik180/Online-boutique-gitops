/*
 * Theme controller: dark mode, color theme, density, font size, product grid.
 * Loaded synchronously in <head> so attributes are set before first paint
 * (no flash of the wrong theme). UI wiring runs after the DOM is ready.
 */
(function () {
  'use strict';

  var KEY = 'ob-prefs';
  var DEFAULTS = { color: 'default', density: 'comfortable', font: 'medium', cols: '3' };
  var ALLOWED = {
    theme: ['light', 'dark'],
    color: ['default', 'ocean', 'sunset', 'forest'],
    density: ['comfortable', 'compact'],
    font: ['small', 'medium', 'large'],
    cols: ['2', '3', '4']
  };

  var root = document.documentElement;
  var mq = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;

  function load() {
    try {
      var raw = window.localStorage.getItem(KEY);
      return raw ? JSON.parse(raw) : {};
    } catch (e) {
      return {};
    }
  }

  function save(prefs) {
    try { window.localStorage.setItem(KEY, JSON.stringify(prefs)); } catch (e) { /* storage blocked */ }
  }

  function clear() {
    try { window.localStorage.removeItem(KEY); } catch (e) { /* storage blocked */ }
  }

  function valid(name, value) {
    return ALLOWED[name].indexOf(value) !== -1;
  }

  function effective(prefs) {
    var out = {};
    out.theme = valid('theme', prefs.theme) ? prefs.theme : (mq && mq.matches ? 'dark' : 'light');
    ['color', 'density', 'font', 'cols'].forEach(function (k) {
      out[k] = valid(k, prefs[k]) ? prefs[k] : DEFAULTS[k];
    });
    return out;
  }

  function apply(prefs) {
    var e = effective(prefs);
    root.setAttribute('data-theme', e.theme);
    root.setAttribute('data-color', e.color);
    root.setAttribute('data-density', e.density);
    root.setAttribute('data-font', e.font);
    root.setAttribute('data-cols', e.cols);
    return e;
  }

  var prefs = load();
  var current = apply(prefs);

  function syncUI() {
    var toggle = document.getElementById('ob-dark-toggle');
    if (toggle) {
      var on = current.theme === 'dark';
      toggle.setAttribute('aria-checked', on ? 'true' : 'false');
      var state = toggle.querySelector('.ob-switch-state');
      if (state) { state.textContent = on ? 'ON' : 'OFF'; }
    }
    var groups = document.querySelectorAll('#ob-panel .ob-group');
    Array.prototype.forEach.call(groups, function (g) {
      var setting = g.getAttribute('data-setting');
      Array.prototype.forEach.call(g.querySelectorAll('button'), function (b) {
        b.setAttribute('aria-pressed', b.getAttribute('data-value') === current[setting] ? 'true' : 'false');
      });
    });
  }

  function set(name, value) {
    if (!valid(name, value)) { return; }
    prefs[name] = value;
    save(prefs);
    current = apply(prefs);
    syncUI();
  }

  function ready() {
    var toggle = document.getElementById('ob-dark-toggle');
    var btn = document.getElementById('ob-customize-btn');
    var panel = document.getElementById('ob-panel');
    var reset = document.getElementById('ob-reset');

    if (toggle) {
      toggle.addEventListener('click', function () {
        set('theme', current.theme === 'dark' ? 'light' : 'dark');
      });
    }

    if (btn && panel) {
      var close = function () {
        panel.hidden = true;
        btn.setAttribute('aria-expanded', 'false');
      };
      btn.addEventListener('click', function (ev) {
        ev.stopPropagation();
        var open = panel.hidden;
        panel.hidden = !open;
        btn.setAttribute('aria-expanded', open ? 'true' : 'false');
      });
      panel.addEventListener('click', function (ev) {
        ev.stopPropagation();
        var b = ev.target.closest ? ev.target.closest('button[data-value]') : null;
        if (!b) { return; }
        var group = b.parentNode;
        set(group.getAttribute('data-setting'), b.getAttribute('data-value'));
      });
      document.addEventListener('click', close);
      document.addEventListener('keydown', function (ev) {
        if (ev.key === 'Escape' && !panel.hidden) { close(); btn.focus(); }
      });
    }

    if (reset) {
      reset.addEventListener('click', function () {
        prefs = {};
        clear();
        current = apply(prefs);
        syncUI();
      });
    }

    syncUI();
  }

  if (mq && mq.addEventListener) {
    mq.addEventListener('change', function () {
      if (!valid('theme', prefs.theme)) { current = apply(prefs); syncUI(); }
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', ready);
  } else {
    ready();
  }
})();
