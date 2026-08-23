(function () {
  'use strict';

  var PLUGIN_ID = 'daily-summary';

  var $ = function (id) { return document.getElementById(id); };
  var state = {
    config: null,
    summaries: [],
    currentIndex: -1,
    currentModel: null,
    running: false,
    loading: true,
    rawValues: {},
  };

  // ---------------------------------------------------------------- bridge
  function bridge(method, params) {
    if (!window.lynai || !window.lynai.call) {
      return Promise.reject(new Error('LynAI bridge 尚未就绪'));
    }
    return window.lynai.call(method, params || {});
  }

  function isReady() {
    return !!(window.lynai && window.lynai.call);
  }

  function waitReady() {
    if (isReady()) return Promise.resolve();
    return new Promise(function (resolve) {
      var timer = setInterval(function () {
        if (isReady()) {
          clearInterval(timer);
          resolve();
        }
      }, 120);
    });
  }

  // ---------------------------------------------------------------- utils
  function pad2(value) {
    return value < 10 ? '0' + value : String(value);
  }

  function dateKey(date) {
    if (!(date instanceof Date) || isNaN(date.getTime())) return null;
    return date.getFullYear() + '-' + pad2(date.getMonth() + 1) + '-' + pad2(date.getDate());
  }

  function todayKey() {
    return dateKey(new Date());
  }

  function parseDateKey(key) {
    if (typeof key !== 'string') return null;
    var match = key.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (!match) return null;
    return new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
  }

  function dateLabel(key, short) {
    var date = parseDateKey(key);
    if (!date) return key;
    var weekdays = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    var text = date.getMonth() + 1 + '月' + date.getDate() + '日';
    if (short) return text;
    return text + ' · ' + weekdays[date.getDay()];
  }

  function escapeHtml(value) {
    return String(value == null ? '' : value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function plainText(markdown, max) {
    var text = String(markdown || '')
      .replace(/```[\s\S]*?```/g, ' ')
      .replace(/[#>*_`~-]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
    if (max > 0 && text.length > max) text = text.slice(0, max) + '…';
    return text;
  }

  function titleFrom(markdown) {
    var lines = String(markdown || '').split(/\r?\n/);
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim();
      if (!line) continue;
      return line.replace(/^#{1,6}\s+/, '').replace(/[*_`>#]/g, '').trim() || '每日总结';
    }
    return '每日总结';
  }

  function sectionsFrom(markdown) {
    var result = [];
    String(markdown || '').split(/\r?\n/).forEach(function (line) {
      var match = line.match(/^(#{1,3})\s+(.+?)\s*$/);
      if (!match) return;
      result.push({ level: match[1].length, title: match[2].replace(/[*_`]/g, '') });
    });
    return result.slice(0, 14);
  }

  // ---------------------------------------------------------------- markdown
  function inlineMarkdown(text) {
    var html = escapeHtml(text);
    html = html.replace(/`([^`]+)`/g, '<code>$1</code>');
    html = html.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
    html = html.replace(/__([^_]+)__/g, '<strong>$1</strong>');
    html = html.replace(/\*([^*]+)\*/g, '<em>$1</em>');
    html = html.replace(/(^|[\s(])(https?:\/\/[^\s<>"']+)/g, function (_, pre, url) {
      return pre + '<span class="link">' + url + '</span>';
    });
    return html;
  }

  function renderMarkdown(markdown) {
    var lines = String(markdown || '').replace(/\r\n/g, '\n').split('\n');
    var html = [];
    var listType = null;
    var codeLines = [];

    function flushList() {
      if (!listType) return;
      html.push('</' + listType + '>');
      listType = null;
    }

    function flushCode() {
      if (!codeLines.length) return;
      html.push('<pre><code>' + escapeHtml(codeLines.join('\n')) + '</code></pre>');
      codeLines = [];
    }

    lines.forEach(function (raw) {
      var line = raw;
      if (/^\s*```/.test(line)) {
        flushList();
        if (codeLines.length) flushCode();
        return;
      }

      var heading = line.match(/^(#{1,3})\s+(.+?)\s*$/);
      if (heading) {
        flushList();
        flushCode();
        var level = heading[1].length;
        html.push('<h' + (level + 1) + '>' + inlineMarkdown(heading[2]) + '</h' + (level + 1) + '>');
        return;
      }

      var quote = line.match(/^>\s?(.*)$/);
      if (quote) {
        flushList();
        flushCode();
        html.push('<blockquote>' + inlineMarkdown(quote[1]) + '</blockquote>');
        return;
      }

      var unordered = line.match(/^\s*[-*+]\s+(.+)$/);
      var ordered = line.match(/^\s*\d+[.)]\s+(.+)$/);
      if (unordered || ordered) {
        flushCode();
        var nextType = unordered ? 'ul' : 'ol';
        if (listType !== nextType) {
          flushList();
          html.push('<' + nextType + '>');
          listType = nextType;
        }
        html.push('<li>' + inlineMarkdown((unordered || ordered)[1]) + '</li>');
        return;
      }

      flushList();
      if (line.trim() === '') {
        flushCode();
        return;
      }
      if (line.trim().startsWith('    ')) {
        codeLines.push(line.replace(/^    /, ''));
        return;
      }
      flushCode();
      html.push('<p>' + inlineMarkdown(line.trim()) + '</p>');
    });

    flushList();
    flushCode();
    return html.join('\n');
  }

  // ---------------------------------------------------------------- render
  function buildSummaries(storage) {
    var values = (storage && storage.values) || {};
    state.rawValues = values;
    var summaries = Object.keys(values)
      .filter(function (key) { return key.indexOf('summary.') === 0; })
      .map(function (key) {
        var value = values[key] || {};
        var date = key.slice('summary.'.length);
        var markdown = value.markdown || '';
        return {
          key: key,
          date: date,
          markdown: markdown,
          title: value.title || titleFrom(markdown),
          modelLabel: value.model_label || value.modelLabel || '每日总结',
          generatedAt: value.generated_at || value.generatedAt || '',
          source: value.source || '',
        };
      })
      .filter(function (item) { return parseDateKey(item.date) !== null; })
      .sort(function (a, b) { return a.date < b.date ? 1 : -1; });

    state.summaries = summaries;
    if (state.currentIndex < 0 && summaries.length > 0) {
      var today = todayKey();
      var todayIndex = summaries.findIndex(function (item) { return item.date === today; });
      state.currentIndex = todayIndex >= 0 ? todayIndex : 0;
    }
    if (state.currentIndex >= summaries.length) state.currentIndex = summaries.length - 1;
  }

  function pruneOldSummaries() {
    var cutoff = new Date();
    cutoff.setHours(0, 0, 0, 0);
    cutoff.setDate(cutoff.getDate() - 90);
    Object.keys(state.rawValues).forEach(function (key) {
      if (key.indexOf('summary.') !== 0) return;
      var date = parseDateKey(key.slice('summary.'.length));
      if (!date || date >= cutoff) return;
      bridge('plugin.storage.remove', { key: key }).catch(function () {});
    });
  }

  function renderRail() {
    var list = $('rail-list');
    $('page-count').textContent = state.summaries.length + ' 篇';
    if (!state.summaries.length) {
      list.innerHTML = '<p class="rail-empty">还没有历史总结</p>';
      return;
    }
    var today = todayKey();
    list.innerHTML = state.summaries.map(function (item, index) {
      var expanded = index === state.currentIndex;
      var sections = sectionsFrom(item.markdown);
      var label = item.date === today ? '今天' : dateLabel(item.date, true);
      var outline = expanded && sections.length
        ? '<div class="page-outline">' + sections.map(function (section, si) {
            return '<a class="outline-link" data-outline="' + si + '" href="#">' +
              escapeHtml(section.title) + '</a>';
          }).join('') + '</div>'
        : '';
      return '<article class="page-card' + (expanded ? ' is-active is-expanded' : '') + '" data-index="' + index + '" style="animation-delay:' + (index * 34) + 'ms">' +
        '<div class="page-card-main">' +
          '<span class="page-card-index">' + pad2(index + 1) + '</span>' +
          '<div class="page-card-title"><strong>' + escapeHtml(item.title) + '</strong>' +
          '<small>' + label + ' · ' + (item.generatedAt ? item.generatedAt.slice(11, 16) : '—') + '</small></div>' +
          '<span class="page-card-chevron"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg></span>' +
        '</div>' + outline +
      '</article>';
    }).join('');
  }

  function renderArticle() {
    var reader = $('reader');
    if (state.loading) return;
    if (!state.summaries.length) {
      reader.innerHTML =
        '<div class="reader-state">' +
          '<div class="state-art"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M20.6 14.2A8.5 8.5 0 1 1 9.8 3.4a7 7 0 0 0 10.8 10.8Z"/></svg></div>' +
          '<div class="empty-copy"><h3>还没有总结</h3><p>每晚按计划自动生成。也可以现在就点右上角「立即总结」，为今天写一篇。</p></div>' +
          '<button class="primary-ghost" id="empty-run" type="button">为今天生成一篇</button>' +
        '</div>';
      $('empty-run').addEventListener('click', function () { runNow(todayKey()); });
      $('pager').hidden = true;
      renderRail();
      return;
    }

    var item = state.summaries[state.currentIndex];
    if (!item) return;
    var body = renderMarkdown(item.markdown);
    var title = titleFrom(item.markdown);
    var generated = item.generatedAt
      ? item.generatedAt.replace('T', ' ').slice(0, 16)
      : '';
    var today = todayKey();
    var isToday = item.date === today;

    reader.innerHTML =
      '<article class="article">' +
        '<div class="article-date">' + dateLabel(item.date) + '</div>' +
        '<h2 class="article-title">' + escapeHtml(title) + '</h2>' +
        '<div class="article-meta">' +
          '<span class="meta-chip is-accent">' + escapeHtml(item.modelLabel || '每日总结') + '</span>' +
          (generated ? '<span class="meta-chip">' + escapeHtml(generated) + '</span>' : '') +
          '<span class="meta-chip">第 ' + (state.currentIndex + 1) + ' 篇 / 共 ' + state.summaries.length + ' 篇</span>' +
          '<span class="article-actions">' +
            '<button class="icon-btn" id="copy-btn" type="button" title="复制全文">' +
              '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>' +
            '</button>' +
            (isToday
              ? '<button class="icon-btn" id="regen-btn" type="button" title="重新生成">' +
                '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5"/></svg>' +
              '</button>'
              : '') +
          '</span>' +
        '</div>' +
        '<div class="article-body">' + body + '</div>' +
      '</article>';

    $('copy-btn').addEventListener('click', function () { copyText(item.markdown); });
    if (isToday) {
      $('regen-btn').addEventListener('click', function () { runNow(item.date); });
    }
    renderPager();
    renderRail();
  }

  function renderPager() {
    var pager = $('pager');
    pager.hidden = state.summaries.length < 2;
    if (pager.hidden) return;
    $('pager-index').textContent = (state.currentIndex + 1) + ' / ' + state.summaries.length;
    $('prev-btn').disabled = state.currentIndex >= state.summaries.length - 1;
    $('next-btn').disabled = state.currentIndex <= 0;
    var dots = $('pager-dots');
    dots.innerHTML = state.summaries.map(function (_, index) {
      return '<span class="' + (index === state.currentIndex ? 'is-active' : '') + '"></span>';
    }).join('');
  }

  function renderTopbar() {
    var cfg = state.config || {};
    var time = cfg.time || '23:00';
    var timeChanged = time !== '23:00';
    $('plan-text').textContent = timeChanged
      ? '计划 ' + time + ' · 同步中'
      : '计划 ' + time;
    $('plan-pill').classList.toggle('is-off', timeChanged);
    $('today-line').textContent = dateLabel(todayKey()) + ' · ' + yearText();
    $('config-time').textContent = time;
    $('config-model').textContent = modelLabel(cfg.model);
  }

  function yearText() {
    return new Date().getFullYear() + ' 年';
  }

  function modelLabel(model) {
    if (!model || !model.modelId) return '跟随当前对话模型';
    return model.modelName || model.modelId;
  }

  // ---------------------------------------------------------------- actions
  function setRunning(running) {
    state.running = running;
    var btn = $('run-btn');
    btn.disabled = running;
    btn.classList.toggle('is-running', running);
    btn.querySelector('.run-btn-label').textContent = running ? '' : '立即总结';
  }

  function renderGenerating(date) {
    $('reader').innerHTML =
      '<div class="reader-state">' +
        '<div class="generating-orbit"><div class="moon"></div></div>' +
        '<div class="empty-copy"><h3>正在为 ' + dateLabel(date) + ' 写总结</h3></div>' +
        '<div class="phase-list">' +
          '<div class="phase is-active" id="phase-1"><span class="phase-dot"></span>收集今天的笔记、任务与日程</div>' +
          '<div class="phase" id="phase-2"><span class="phase-dot"></span>交给模型阅读与整理</div>' +
          '<div class="phase" id="phase-3"><span class="phase-dot"></span>保存到总结分页</div>' +
        '</div>' +
        '<div class="progress"><span></span></div>' +
      '</div>';
    var index = 0;
    window.__summaryPhaseTimer = setInterval(function () {
      index = (index + 1) % 3;
      [1, 2, 3].forEach(function (n) {
        var phase = $('phase-' + n);
        if (phase) phase.classList.toggle('is-active', n === index + 1);
      });
    }, 2600);
  }

  function stopPhases() {
    if (window.__summaryPhaseTimer) {
      clearInterval(window.__summaryPhaseTimer);
      window.__summaryPhaseTimer = null;
    }
  }

  function runNow(date) {
    if (state.running) return;
    var target = date || todayKey();
    setRunning(true);
    renderGenerating(target);
    bridge('plugin.call', {
      pluginId: PLUGIN_ID,
      functionName: 'generate_now',
      arguments: { date: target },
    }).then(function () {
      stopPhases();
      toast('总结已生成');
      return loadData({ refreshOnly: true });
    }).catch(function (error) {
      stopPhases();
      renderError(error && error.message ? error.message : String(error), target);
      setRunning(false);
    }).then(function () {
      setRunning(false);
    });
  }

  function renderError(message, retryDate) {
    $('reader').innerHTML =
      '<div class="reader-state">' +
        '<div class="error-card">' +
          '<h3>生成失败</h3>' +
          '<p>' + escapeHtml(message) + '</p>' +
          '<div class="error-actions">' +
            '<button class="primary-ghost" id="retry-btn" type="button">重试</button>' +
          '</div>' +
        '</div>' +
      '</div>';
    $('retry-btn').addEventListener('click', function () { runNow(retryDate || todayKey()); });
  }

  function copyText(text) {
    function fallback() {
      var area = document.createElement('textarea');
      area.value = text;
      area.style.position = 'fixed';
      area.style.opacity = '0';
      document.body.appendChild(area);
      area.select();
      try { document.execCommand('copy'); toast('已复制到剪贴板'); } catch (_) { toast('复制失败', true); }
      document.body.removeChild(area);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function () {
        toast('已复制到剪贴板');
      }).catch(fallback);
    } else {
      fallback();
    }
  }

  function toast(message, isError) {
    var old = document.querySelector('.toast');
    if (old) old.remove();
    var node = document.createElement('div');
    node.className = 'toast' + (isError ? ' is-error' : '');
    node.textContent = message;
    document.body.appendChild(node);
    setTimeout(function () { node.remove(); }, 2800);
  }

  // ---------------------------------------------------------------- data
  function loadData(options) {
    options = options || {};
    if (!options.refreshOnly) {
      state.loading = true;
      $('reader').innerHTML = '<div class="reader-state"><div class="state-icon shimmer-ring"></div><p>正在整理每天的总结…</p></div>';
    }
    return Promise.all([
      bridge('plugin.config.read'),
      bridge('plugin.storage.get'),
      bridge('model.current', { category: 'chat' }).catch(function () { return { ok: true, model: '—' }; }),
      bridge('system.status').catch(function () { return { ok: true, timestamp: new Date().toISOString() }; }),
    ]).then(function (results) {
      var configResult = results[0];
      var storage = results[1];
      var model = results[2];
      var system = results[3];

      state.config = (configResult && configResult.values) || {};
      state.currentModel = model;
      buildSummaries(storage);
      pruneOldSummaries();
      renderTopbar();
      renderArticle();
      state.loading = false;
    }).catch(function (error) {
      state.loading = false;
      renderError(error && error.message ? error.message : String(error));
    });
  }

  // ---------------------------------------------------------------- navigation
  function selectIndex(index) {
    if (index < 0 || index >= state.summaries.length) return;
    state.currentIndex = index;
    renderArticle();
    var rail = $('rail-list');
    var card = rail && rail.querySelector('[data-index="' + index + '"]');
    if (card && card.scrollIntoView) card.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  }

  function selectDate(date) {
    var index = state.summaries.findIndex(function (item) { return item.date === date; });
    if (index >= 0) selectIndex(index);
  }

  function bindEvents() {
    $('run-btn').addEventListener('click', function () { runNow(todayKey()); });
    $('prev-btn').addEventListener('click', function () {
      if (state.currentIndex < state.summaries.length - 1) selectIndex(state.currentIndex + 1);
    });
    $('next-btn').addEventListener('click', function () {
      if (state.currentIndex > 0) selectIndex(state.currentIndex - 1);
    });

    $('rail-list').addEventListener('click', function (event) {
      var outline = event.target.closest('.outline-link');
      if (outline) {
        event.preventDefault();
        var card = outline.closest('.page-card');
        var index = Number(card && card.dataset.index);
        selectIndex(index);
        var sectionIndex = Number(outline.dataset.outline);
        var sections = state.summaries[index] ? sectionsFrom(state.summaries[index].markdown) : [];
        var target = document.querySelectorAll('.article-body h2, .article-body h3')[sectionIndex];
        if (target && target.scrollIntoView) target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        return;
      }
      var card = event.target.closest('.page-card');
      if (card) selectIndex(Number(card.dataset.index));
    });

    document.addEventListener('keydown', function (event) {
      if (event.key === 'ArrowLeft') {
        if (state.currentIndex < state.summaries.length - 1) selectIndex(state.currentIndex + 1);
      } else if (event.key === 'ArrowRight') {
        if (state.currentIndex > 0) selectIndex(state.currentIndex - 1);
      }
    });

    var touchStartX = null;
    var reader = $('reader');
    reader.addEventListener('touchstart', function (event) {
      touchStartX = event.changedTouches[0].clientX;
    }, { passive: true });
    reader.addEventListener('touchend', function (event) {
      if (touchStartX == null) return;
      var delta = event.changedTouches[0].clientX - touchStartX;
      if (Math.abs(delta) > 60) {
        if (delta > 0 && state.currentIndex < state.summaries.length - 1) selectIndex(state.currentIndex + 1);
        if (delta < 0 && state.currentIndex > 0) selectIndex(state.currentIndex - 1);
      }
      touchStartX = null;
    }, { passive: true });

    var settingsOpen = false;
    function setSettings(open) {
      settingsOpen = open;
      $('settings-sheet').classList.toggle('is-open', open);
      $('settings-sheet').setAttribute('aria-hidden', String(!open));
      $('scrim').hidden = !open;
    }
    $('settings-btn').addEventListener('click', function () { setSettings(true); });
    $('settings-close').addEventListener('click', function () { setSettings(false); });
    $('scrim').addEventListener('click', function () { setSettings(false); });
  }

  function init() {
    bindEvents();
    waitReady().then(function () { return loadData(); });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
