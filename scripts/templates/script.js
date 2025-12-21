// Navigation data - will be replaced with actual data
const navigationData = {{NAVIGATION_DATA}};

// Load navigation
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

// Theme support
document.addEventListener('DOMContentLoaded', () => {
    // Check for saved theme preference or default to dark
    const theme = localStorage.getItem('theme') || 'dark';
    document.body.setAttribute('data-theme', theme);
});
