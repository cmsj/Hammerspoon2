// Navigation data - will be replaced with actual data
const navigationData = {{NAVIGATION_DATA}};

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

// Filter nav links by text match on search input
function initSearch() {
    const searchInput = document.getElementById('search-input');
    if (!searchInput) return;

    searchInput.addEventListener('input', () => {
        const query = searchInput.value.toLowerCase().trim();
        const links = document.querySelectorAll('.nav-section a');

        links.forEach(link => {
            const text = link.textContent.toLowerCase();
            if (query === '' || text.includes(query)) {
                link.classList.remove('hidden');
            } else {
                link.classList.add('hidden');
            }
        });
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

// Apply dark theme and initialise syntax highlighting
document.addEventListener('DOMContentLoaded', () => {
    document.documentElement.setAttribute('data-theme', 'dark');

    if (typeof hljs !== 'undefined') {
        hljs.highlightAll();
    }
});
