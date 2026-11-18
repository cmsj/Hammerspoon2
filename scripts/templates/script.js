// Navigation and search data injected at build time
const navigationData = {{NAVIGATION_DATA}};
const searchIndex = {{SEARCH_INDEX}};

// Sidebar tree state kept for the browsing session: the pages whose entries
// the reader has expanded, and how far the sidebar was scrolled
const NAV_EXPANDED_KEY = 'hs2-docs-nav-expanded';
const NAV_SCROLL_KEY = 'hs2-docs-nav-scroll';

function readSessionValue(key, fallback) {
    try {
        const value = sessionStorage.getItem(key);
        return value === null ? fallback : JSON.parse(value);
    } catch (e) {
        return fallback;
    }
}

function writeSessionValue(key, value) {
    try {
        sessionStorage.setItem(key, JSON.stringify(value));
    } catch (e) {}
}

// A tree row: a disclosure toggle (or a spacer, to keep labels aligned)
// followed by the entry's link
function navRow(link, hasChildren, expanded) {
    const toggle = hasChildren
        ? `<button type="button" class="nav-toggle" aria-expanded="${expanded}" aria-label="Show contents"></button>`
        : '<span class="nav-toggle-spacer"></span>';
    return `<div class="nav-row">${toggle}${link}</div>`;
}

// The sections or members under a sidebar entry. On the current page they are
// plain fragment links, tagged so initNavTracking() can follow the reader.
function renderNavChildren(children, pageUrl, isCurrent) {
    const nested = children.some(child => child.children && child.children.length);
    const items = children.map(child => {
        const href = isCurrent ? `#${child.id}` : `${pageUrl}#${child.id}`;
        const target = isCurrent ? ` data-nav-target="${child.id}"` : '';
        const kind = child.kind ? ` class="nav-${child.kind}"` : '';
        const link = `<a href="${href}"${target}${kind}>${child.html}</a>`;
        if (!nested) return `<li>${link}</li>`;
        const hasChildren = child.children && child.children.length > 0;
        return `<li class="nav-node">${navRow(link, hasChildren, false)}` +
            (hasChildren ? renderNavChildren(child.children, pageUrl, isCurrent) : '') +
            '</li>';
    });
    return `<ul class="nav-children">${items.join('')}</ul>`;
}

// Build the left sidebar: a collapsible tree of every guide, module and type,
// with the current page's entry expanded
function loadNavigation(currentPage) {
    const sidebar = document.querySelector('.sidebar-left');
    if (!sidebar) return;

    const expandedPages = new Set(readSessionValue(NAV_EXPANDED_KEY, []));
    const sections = [
        ['guides-nav', navigationData.guides],
        ['modules-nav', navigationData.modules],
        ['types-nav', navigationData.types]
    ];

    for (const [containerId, entries] of sections) {
        const container = document.getElementById(containerId);
        if (!container) continue;
        container.innerHTML = '<ul class="nav-tree">' + entries.map(entry => {
            const isCurrent = entry.page === currentPage;
            const hasChildren = entry.children.length > 0;
            const expanded = hasChildren && (isCurrent || expandedPages.has(entry.page));
            const classes = ['nav-node', isCurrent ? 'nav-current' : '', expanded ? 'expanded' : '']
                .filter(Boolean).join(' ');
            const link = `<a href="${entry.url}" class="${isCurrent ? 'active' : ''}">${entry.name}</a>`;
            return `<li class="${classes}" data-page="${entry.page}">` +
                navRow(link, hasChildren, expanded) +
                (hasChildren ? renderNavChildren(entry.children, entry.url, isCurrent) : '') +
                '</li>';
        }).join('') + '</ul>';
    }

    sidebar.addEventListener('click', (e) => {
        const toggle = e.target.closest('.nav-toggle');
        if (!toggle) return;
        const node = toggle.closest('.nav-node');
        const expanded = node.classList.toggle('expanded');
        toggle.setAttribute('aria-expanded', expanded);
        if (node.dataset.page) {
            if (expanded) {
                expandedPages.add(node.dataset.page);
            } else {
                expandedPages.delete(node.dataset.page);
            }
            writeSessionValue(NAV_EXPANDED_KEY, [...expandedPages]);
        } else {
            // A section within a page: leave it as the reader set it, rather
            // than following the scroll position
            node.dataset.pinned = 'true';
        }
    });

    // Keep the sidebar where the reader left it, unless that leaves the
    // current page's entry out of view, in which case bring it to the top so
    // its contents are visible too
    sidebar.scrollTop = readSessionValue(NAV_SCROLL_KEY, 0);
    window.addEventListener('pagehide', () => writeSessionValue(NAV_SCROLL_KEY, sidebar.scrollTop));
    const active = sidebar.querySelector('.nav-current > .nav-row');
    if (active) {
        const row = active.getBoundingClientRect();
        const visible = sidebar.getBoundingClientRect();
        if (row.top < visible.top || row.bottom > visible.bottom) {
            sidebar.scrollTop += row.top - visible.top - 8;
        }
    }
}

// Populate the right-hand "On This Page" TOC
function generateTOC() {
    const tocNav = document.getElementById('toc-nav');
    const tocSidebar = document.querySelector('.toc-sidebar');
    if (!tocNav || !tocSidebar) return;

    const properties = Array.from(document.querySelectorAll('.content .property[id]'));
    const methods = Array.from(document.querySelectorAll('.content .method[id]'));

    if (properties.length === 0 && methods.length === 0) {
        tocSidebar.style.display = 'none';
        return;
    }

    // Strip module/type prefix and return type from h3 text.
    // For methods, keep the parameter list: "hs.m.show(a, b) -> Bool" → "show(a, b)"
    // For properties, keep just the name: "hs.m.watcherInterval" → "watcherInterval"
    function tocLabel(el) {
        const h3 = el.querySelector('h3');
        if (!h3) return el.id;
        let text = h3.textContent.trim();
        // Strip " -> ReturnType" suffix first
        text = text.replace(/\s*->\s*\S+.*$/, '');
        // Strip "prefix." up to the last dot before the opening paren (methods)
        // or before end of string (properties)
        const parenIdx = text.indexOf('(');
        const searchEnd = parenIdx !== -1 ? parenIdx : text.length;
        const lastDot = text.lastIndexOf('.', searchEnd - 1);
        if (lastDot !== -1) text = text.slice(lastDot + 1);
        return text.trim();
    }

    let html = '';
    if (properties.length > 0) {
        html += '<div class="toc-section-label">Properties</div>';
        html += properties.map(el =>
            `<a href="#${el.id}" data-toc-target="${el.id}">${tocLabel(el)}</a>`
        ).join('');
    }
    if (methods.length > 0) {
        html += '<div class="toc-section-label">Methods</div>';
        html += methods.map(el =>
            `<a href="#${el.id}" data-toc-target="${el.id}">${tocLabel(el)}</a>`
        ).join('');
    }
    tocNav.innerHTML = html;
}

// Wrap each <pre> in a .code-block div and add a toolbar with a Copy button
function addCopyButtons() {
    // Only target pre elements not already inside a .code-block
    const pres = document.querySelectorAll('pre:not(.code-block pre)');

    pres.forEach(pre => {
        // Determine language label from the first code child's class
        let lang = 'code';
        const codeEl = pre.querySelector('code');
        if (codeEl) {
            const langClass = Array.from(codeEl.classList).find(c => c.startsWith('language-'));
            if (langClass) {
                lang = langClass.replace('language-', '');
            }
        }

        // Build wrapper
        const wrapper = document.createElement('div');
        wrapper.className = 'code-block';

        // Build toolbar
        const toolbar = document.createElement('div');
        toolbar.className = 'code-block-toolbar';

        const langLabel = document.createElement('span');
        langLabel.className = 'code-block-lang';
        langLabel.textContent = lang;

        const copyBtn = document.createElement('button');
        copyBtn.className = 'copy-btn';
        copyBtn.textContent = 'Copy';
        copyBtn.addEventListener('click', () => {
            const text = pre.textContent || '';
            navigator.clipboard.writeText(text).then(() => {
                copyBtn.textContent = 'Copied!';
                copyBtn.classList.add('copied');
                setTimeout(() => {
                    copyBtn.textContent = 'Copy';
                    copyBtn.classList.remove('copied');
                }, 2000);
            }).catch(() => {
                // Fallback for browsers without clipboard API
                copyBtn.textContent = 'Error';
                setTimeout(() => {
                    copyBtn.textContent = 'Copy';
                }, 2000);
            });
        });

        toolbar.appendChild(langLabel);
        toolbar.appendChild(copyBtn);

        // Insert wrapper before pre, then move pre inside
        pre.parentNode.insertBefore(wrapper, pre);
        wrapper.appendChild(toolbar);
        wrapper.appendChild(pre);
    });
}

// Full-text search across all properties and methods, with rich result preview
function initSearch() {
    const searchInput = document.getElementById('search-input');
    const resultsPanel = document.getElementById('search-results');
    if (!searchInput || !resultsPanel) return;

    let selectedIndex = -1;
    let currentResults = [];

    function setSelected(idx) {
        selectedIndex = idx;
        const items = resultsPanel.querySelectorAll('.search-result-item');
        items.forEach((item, i) => item.classList.toggle('search-result-selected', i === idx));
        if (idx >= 0 && items[idx]) {
            items[idx].scrollIntoView({ block: 'nearest' });
        }
    }

    function showResults(results) {
        currentResults = results;
        selectedIndex = -1;

        if (results.length === 0) {
            resultsPanel.hidden = true;
            return;
        }

        resultsPanel.innerHTML = results.map((r, i) => {
            const desc = r.description.length > 120
                ? r.description.slice(0, 120) + '…'
                : r.description;
            return `<a href="${r.url}" class="search-result-item" data-index="${i}">` +
                `<span class="search-result-name">${r.fullName}</span>` +
                `<span class="search-result-desc">${desc}</span>` +
                `</a>`;
        }).join('');

        resultsPanel.hidden = false;
    }

    function clearResults() {
        currentResults = [];
        selectedIndex = -1;
        resultsPanel.hidden = true;
        resultsPanel.innerHTML = '';
    }

    searchInput.addEventListener('input', () => {
        const query = searchInput.value.toLowerCase().trim();

        if (query.length < 2) { clearResults(); return; }

        const results = searchIndex.filter(item =>
            item.fullName.toLowerCase().includes(query) ||
            item.description.toLowerCase().includes(query)
        ).slice(0, 10);

        showResults(results);
    });

    searchInput.addEventListener('keydown', (e) => {
        if (resultsPanel.hidden) return;

        if (e.key === 'ArrowDown') {
            e.preventDefault();
            setSelected(Math.min(selectedIndex + 1, currentResults.length - 1));
        } else if (e.key === 'ArrowUp') {
            e.preventDefault();
            setSelected(Math.max(selectedIndex - 1, -1));
        } else if (e.key === 'Enter' && selectedIndex >= 0) {
            e.preventDefault();
            window.location.href = currentResults[selectedIndex].url;
            searchInput.value = '';
            clearResults();
        } else if (e.key === 'Escape') {
            searchInput.value = '';
            clearResults();
            searchInput.blur();
        }
    });

    // Close panel when clicking outside the search wrapper
    document.addEventListener('click', (e) => {
        if (!e.target.closest('.search-wrapper')) clearResults();
    });

    // Clear input after a result link is followed (panel element handles the click)
    resultsPanel.addEventListener('click', () => {
        searchInput.value = '';
        clearResults();
    });
}

// Highlight current section in the TOC using IntersectionObserver
function initTOCObserver() {
    const tocNav = document.getElementById('toc-nav');
    if (!tocNav) return;

    const items = document.querySelectorAll('.content .method[id], .content .property[id]');
    if (items.length === 0) return;

    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            const id = entry.target.id;
            const tocLink = tocNav.querySelector(`[data-toc-target="${id}"]`);
            if (!tocLink) return;

            if (entry.isIntersecting) {
                // Remove active from all, set on current
                tocNav.querySelectorAll('a').forEach(a => a.classList.remove('toc-active'));
                tocLink.classList.add('toc-active');
            }
        });
    }, {
        rootMargin: '-52px 0px -60% 0px',
        threshold: 0
    });

    items.forEach(el => observer.observe(el));
}

// Highlight the section or member being read in the current page's sidebar
// entry, expanding the guide section that contains it
function initNavTracking() {
    const current = document.querySelector('.nav-node.nav-current');
    if (!current) return;

    const targets = Array.from(current.querySelectorAll('a[data-nav-target]'))
        .map(link => ({ link, element: document.getElementById(link.dataset.navTarget) }))
        .filter(target => target.element);
    if (targets.length === 0) return;

    const sectionNodes = Array.from(current.querySelectorAll('.nav-children .nav-node'));
    let activeLink;

    function update() {
        // The active target is the last one scrolled past the header; none is
        // active while the reader is still above the first
        const threshold = document.querySelector('.top-header').offsetHeight + 24;
        let active = null;
        for (const target of targets) {
            if (target.element.getBoundingClientRect().top > threshold) break;
            active = target;
        }
        // At the bottom of the page, later targets may never reach the top
        const scrollable = document.documentElement.scrollHeight > window.innerHeight;
        if (scrollable && window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2) {
            active = targets[targets.length - 1];
        }
        const link = active ? active.link : null;
        if (link === activeLink) return;
        activeLink = link;

        targets.forEach(target => target.link.classList.toggle('outline-active', target.link === link));
        for (const node of sectionNodes) {
            if (node.dataset.pinned) continue;
            const expanded = link !== null && node.contains(link);
            node.classList.toggle('expanded', expanded);
            node.querySelector(':scope > .nav-row > .nav-toggle')?.setAttribute('aria-expanded', expanded);
        }
        if (link) link.scrollIntoView({ block: 'nearest' });
    }

    let scheduled = false;
    window.addEventListener('scroll', () => {
        if (scheduled) return;
        scheduled = true;
        requestAnimationFrame(() => {
            scheduled = false;
            update();
        });
    }, { passive: true });
    window.addEventListener('hashchange', update);
    update();
}

// Apply dark theme and initialise syntax highlighting
document.addEventListener('DOMContentLoaded', () => {
    document.documentElement.setAttribute('data-theme', 'dark');

    if (typeof hljs !== 'undefined') {
        hljs.highlightAll();
    }
});
