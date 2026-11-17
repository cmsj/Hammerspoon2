// Navigation and search data injected at build time
const navigationData = {{NAVIGATION_DATA}};
const searchIndex = {{SEARCH_INDEX}};

// Load navigation links into left sidebar
function loadNavigation(currentPage) {
    const modulesNav = document.getElementById('modules-nav');
    const typesNav = document.getElementById('types-nav');

    if (modulesNav) {
        modulesNav.innerHTML = navigationData.modules.map(m =>
            `<a href="${m.url}" class="${currentPage === m.name ? 'active' : ''}">${m.name}</a>`
        ).join('');
    }

    if (typesNav) {
        typesNav.innerHTML = navigationData.types.map(t =>
            `<a href="${t.url}" class="${currentPage === t.name ? 'active' : ''}">${t.name}</a>`
        ).join('');
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

// On guide pages, highlight the section being read in the sidebar outline and
// expand its sub-sections
function initGuideOutline() {
    const outline = document.getElementById('guide-outline');
    if (!outline) return;

    const links = Array.from(outline.querySelectorAll('a[data-outline-target]'));
    const headings = links
        .map(a => document.getElementById(a.dataset.outlineTarget))
        .filter(Boolean);
    if (headings.length === 0) return;

    let currentId = null;

    function update() {
        // The current section is the last heading scrolled past the header
        // (or the first one, before any has been reached)
        const threshold = document.querySelector('.top-header').offsetHeight + 24;
        let current = headings[0];
        for (const heading of headings) {
            if (heading.getBoundingClientRect().top > threshold) break;
            current = heading;
        }
        // At the bottom of the page, later headings may never reach the top
        if (window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2) {
            current = headings[headings.length - 1];
        }
        if (current.id === currentId) return;
        currentId = current.id;

        const activeLink = outline.querySelector(`[data-outline-target="${CSS.escape(currentId)}"]`);
        links.forEach(a => a.classList.toggle('outline-active', a === activeLink));
        const activeSection = activeLink.closest('.guide-outline > li');
        outline.querySelectorAll(':scope > li').forEach(li =>
            li.classList.toggle('expanded', li === activeSection));
        activeLink.scrollIntoView({ block: 'nearest' });
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
