#!/usr/bin/env node

/**
 * Custom HTML Documentation Generator for Hammerspoon 2
 *
 * This generator creates clean, organized documentation that properly separates:
 * - Modules (hs.alert, hs.window, etc.) with their factory methods
 * - Types (HSAlert, HSFont, etc.) with their instance properties and methods
 */

const fs = require('fs');
const path = require('path');
const nunjucks = require('nunjucks');
const { marked } = require('marked');
const hljs = require('highlight.js');

const JSON_DIR = path.join(__dirname, '..', 'docs', 'json');
const OUTPUT_DIR = path.join(__dirname, '..', 'docs', 'html');
const COMBINED_DIR = path.join(JSON_DIR, 'combined');
const TEMPLATES_DIR = path.join(__dirname, 'templates');

// Configure marked with highlight.js
marked.setOptions({
    highlight: function(code, lang) {
        if (lang && hljs.getLanguage(lang)) {
            try {
                return hljs.highlight(code, { language: lang }).value;
            } catch (err) {}
        }
        return code;
    }
});

// Ensure output directory exists
if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

// Configure Nunjucks
const env = nunjucks.configure(TEMPLATES_DIR, {
    autoescape: true,
    trimBlocks: true,
    lstripBlocks: true
});

// Add custom filters
env.addFilter('formatType', function(swiftType) {
    return formatType(swiftType);
});

env.addFilter('extractPropertyType', function(signature) {
    const typeMatch = signature.match(/var\s+\w+\s*:\s*([^{]+)/);
    return typeMatch ? typeMatch[1].trim() : 'any';
});

env.addFilter('filterInitMethods', function(methods, isGlobal) {
    if (!methods) return [];
    return methods.filter(m => m.name !== 'init' || isGlobal);
});

env.addFilter('markdown', function(text) {
    if (!text) return '';
    return marked(text);
});

env.addFilter('githubSourceUrl', function(item) {
    if (!item || !item.filePath || !item.lineNumber) {
        return null;
    }
    // GitHub repo URL - update this if the repo changes
    const baseUrl = 'https://github.com/cmsj/Hammerspoon2/blob/main';
    // URL encode the file path
    const encodedPath = item.filePath.split('/').map(encodeURIComponent).join('/');
    return `${baseUrl}/${encodedPath}#L${item.lineNumber}`;
});

// Load static asset templates (CSS and JS are not Nunjucks templates)
let cssTemplate = '';
let scriptTemplate = '';

function loadAssetTemplates() {
    cssTemplate = fs.readFileSync(path.join(TEMPLATES_DIR, 'styles.css'), 'utf8');
    scriptTemplate = fs.readFileSync(path.join(TEMPLATES_DIR, 'script.js'), 'utf8');
}

/**
 * Validate that required documentation fields are present
 */
function validateMethod(method, context) {
    if (!method.description || method.description.trim() === '') {
        throw new Error(`Missing description for method ${context}.${method.name}`);
    }

    // Validate parameters have descriptions
    if (method.params) {
        for (const param of method.params) {
            if (!param.description || param.description.trim() === '') {
                throw new Error(`Missing description for parameter "${param.name}" in ${context}.${method.name}`);
            }
        }
    }

    // Validate returns has description if present
    if (method.returns && (!method.returns.description || method.returns.description.trim() === '')) {
        throw new Error(`Missing description for return value in ${context}.${method.name}`);
    }
}

function validateProperty(property, context) {
    if (!property.description || property.description.trim() === '') {
        throw new Error(`Missing description for property ${context}.${property.name}`);
    }
}

function validateType(protocol, typeName) {
    if (!protocol.description || protocol.description.trim() === '') {
        throw new Error(`Missing description for type ${typeName}`);
    }
}

/**
 * Convert Swift type to display type
 */
function formatType(swiftType) {
    const typeMap = {
        'String': 'string',
        'Int': 'number',
        'Double': 'number',
        'Float': 'number',
        'Bool': 'boolean',
        'TimeInterval': 'number',
        'UInt32': 'number',
        'Any': 'any'
    };

    // Handle arrays
    if (swiftType.match(/^\[([^\]:]+)\]$/)) {
        const inner = swiftType.match(/^\[([^\]:]+)\]$/)[1];
        return `${formatType(inner)}[]`;
    }

    // Handle dictionaries
    if (swiftType.match(/^\[([^:]+):\s*([^\]]+)\]$/)) {
        const match = swiftType.match(/^\[([^:]+):\s*([^\]]+)\]$/);
        return `{[key: ${formatType(match[1])}]: ${formatType(match[2])}}`;
    }

    // Handle optionals
    const cleanType = swiftType.replace(/\?$/, '');
    return typeMap[cleanType] || cleanType;
}

/**
 * Generate module documentation page
 */
function generateModulePage(moduleData) {
    const moduleName = moduleData.name;

    // With the flattened structure, we can use methods and types directly
    const moduleMethods = moduleData.methods || [];
    const typeDefinitions = moduleData.types || [];

    // Validate all methods
    for (const method of moduleMethods) {
        validateMethod(method, moduleName);
    }

    // Render template
    const html = nunjucks.render('module.njk', {
        title: moduleName,
        currentPage: moduleName,
        module: moduleData,
        typeDefinitions: typeDefinitions,
        methods: moduleMethods
    });

    const outputPath = path.join(OUTPUT_DIR, `${moduleName}.html`);
    fs.writeFileSync(outputPath, html);
    console.log(`  ✓ Generated ${moduleName}.html`);
}

/**
 * Generate type documentation page
 */
function generateTypePage(typeName, protocol, isGlobal = false) {
    // Validate type has required documentation
    validateType(protocol, typeName);

    // Validate properties
    const properties = protocol.properties || [];
    for (const prop of properties) {
        validateProperty(prop, typeName);
    }

    // Validate methods
    const methods = protocol.methods || [];
    for (const method of methods) {
        if (method.name !== 'init' || isGlobal) {
            validateMethod(method, typeName);
        }
    }

    // Render template
    const html = nunjucks.render('type.njk', {
        title: typeName,
        currentPage: typeName,
        typeName: typeName,
        protocol: protocol,
        isGlobal: isGlobal
    });

    const outputPath = path.join(OUTPUT_DIR, `${typeName}.html`);
    fs.writeFileSync(outputPath, html);
    console.log(`  ✓ Generated ${typeName}.html`);
}

/**
 * Generate index page
 */
function generateIndexPage(modules, types) {
    // Render template
    const html = nunjucks.render('index.njk', {
        title: 'Home',
        currentPage: 'index',
        modules: modules,
        types: types
    });

    const outputPath = path.join(OUTPUT_DIR, 'index.html');
    fs.writeFileSync(outputPath, html);
    console.log(`  ✓ Generated index.html`);
}

/**
 * Generate JavaScript for navigation
 */
function generateJavaScript(modules, types) {
    const navigationData = {
        modules: modules.map(m => ({ name: m.name, url: m.name + '.html' })),
        types: types.map(t => ({ name: t, url: t + '.html' }))
    };

    const script = scriptTemplate.replace(
        '{{NAVIGATION_DATA}}',
        JSON.stringify(navigationData, null, 2)
    );

    const outputPath = path.join(OUTPUT_DIR, 'script.js');
    fs.writeFileSync(outputPath, script);
    console.log(`  ✓ Generated script.js`);
}

/**
 * Generate CSS
 */
function generateCSS() {
    const outputPath = path.join(OUTPUT_DIR, 'styles.css');
    fs.writeFileSync(outputPath, cssTemplate);
    console.log(`  ✓ Generated styles.css`);
}

/**
 * Copy highlight.js from node_modules to output directory
 */
function copyHighlightJS() {
    const hljsSource = path.join(__dirname, '..', 'node_modules', '@highlightjs', 'cdn-assets', 'highlight.min.js');
    const hljsOutput = path.join(OUTPUT_DIR, 'highlight.min.js');
    fs.copyFileSync(hljsSource, hljsOutput);
    console.log(`  ✓ Copied highlight.min.js`);
}

/**
 * Main execution
 */
function main() {
    console.log('Generating Hammerspoon 2 HTML Documentation...\n');

    // Load asset templates (CSS and JS)
    loadAssetTemplates();

    // Load index
    const indexPath = path.join(JSON_DIR, 'index.json');
    const index = JSON.parse(fs.readFileSync(indexPath, 'utf8'));

    // Generate module pages
    console.log('Generating module pages:');
    for (const module of index.modules) {
        const modulePath = path.join(JSON_DIR, `${module.name}.json`);
        const moduleData = JSON.parse(fs.readFileSync(modulePath, 'utf8'));
        generateModulePage(moduleData);

        // Generate type pages for types defined in this module
        for (const typeDef of moduleData.types || []) {
            const typeName = typeDef.name.replace(/API$/, '');
            generateTypePage(typeName, typeDef, true);
        }
    }

    // Generate global type pages
    console.log('\nGenerating type pages:');
    const allTypes = [];
    if (index.types) {
        const typesPath = path.join(JSON_DIR, 'types.json');
        const typesData = JSON.parse(fs.readFileSync(typesPath, 'utf8'));

        for (const typeDef of typesData.types || []) {
            const typeName = typeDef.name.replace(/(API|JSExports?)$/, '');
            allTypes.push(typeName);
            generateTypePage(typeName, typeDef, true);
        }
    }

    // Collect all type names from modules too
    for (const module of index.modules) {
        const modulePath = path.join(JSON_DIR, `${module.name}.json`);
        const moduleData = JSON.parse(fs.readFileSync(modulePath, 'utf8'));

        for (const typeDef of moduleData.types || []) {
            const typeName = typeDef.name.replace(/API$/, '');
            if (!allTypes.includes(typeName)) {
                allTypes.push(typeName);
            }
        }
    }

    // Generate index page
    console.log('\nGenerating index and assets:');
    generateIndexPage(index.modules, allTypes);

    // Generate JavaScript and CSS
    generateJavaScript(index.modules, allTypes);
    generateCSS();
    copyHighlightJS();

    console.log(`\n✅ HTML documentation generated successfully!`);
    console.log(`   Output directory: ${OUTPUT_DIR}`);
    console.log(`   Open docs/html/index.html in your browser`);
}

main();
