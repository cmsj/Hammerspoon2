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

const JSON_DIR = path.join(__dirname, '..', 'docs', 'json');
const OUTPUT_DIR = path.join(__dirname, '..', 'docs', 'html');
const COMBINED_DIR = path.join(JSON_DIR, 'combined');
const TEMPLATES_DIR = path.join(__dirname, 'templates');

// Ensure output directory exists
if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

// Load templates
let htmlTemplate = '';
let cssTemplate = '';
let scriptTemplate = '';

function loadTemplates() {
    htmlTemplate = fs.readFileSync(path.join(TEMPLATES_DIR, 'page.html'), 'utf8');
    cssTemplate = fs.readFileSync(path.join(TEMPLATES_DIR, 'styles.css'), 'utf8');
    scriptTemplate = fs.readFileSync(path.join(TEMPLATES_DIR, 'script.js'), 'utf8');
}

/**
 * Generate HTML page from template
 */
function generatePage(title, content, currentPage = '') {
    return htmlTemplate
        .replace('{{TITLE}}', title)
        .replace('{{CONTENT}}', content)
        .replace('{{CURRENT_PAGE}}', currentPage);
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

    // Separate module methods from type definitions
    const moduleMethods = [];
    const typeDefinitions = [];

    for (const protocol of moduleData.swift.protocols) {
        if (protocol.type === 'typedef') {
            typeDefinitions.push(protocol);
        } else {
            // Regular module protocol - add all methods
            moduleMethods.push(...protocol.methods);
        }
    }

    // Add JavaScript functions as module methods
    if (moduleData.javascript && moduleData.javascript.functions) {
        for (const func of moduleData.javascript.functions) {
            moduleMethods.push({
                name: func.name,
                signature: `function ${func.name}(${func.params.join(', ')})`,
                description: func.documentation?.description || '',
                params: func.documentation?.params || func.params.map((name, idx) => ({
                    name: name,
                    type: 'any',
                    description: ''
                })),
                returns: func.documentation?.returns || null
            });
        }
    }

    let content = `
        <div class="page-header">
            <h1>${moduleName}</h1>
            <p class="module-type">Module</p>
        </div>

        <div class="section">`;

    // Always show type definitions section
    content += `
            <h2>Types</h2>`;

    if (typeDefinitions.length > 0) {
        content += `
            <p>This module provides the following types:</p>
            <ul class="type-list">`;

        for (const typeDef of typeDefinitions) {
            const typeName = typeDef.name.replace(/API$/, '');
            content += `
                <li>
                    <a href="${typeName}.html" class="type-link">${typeName}</a>
                </li>`;
        }

        content += `
            </ul>`;
    } else {
        content += `
            <p>This module does not provide any types.</p>`;
    }

    // Always show module methods section
    content += `
            <h2>Methods</h2>`;

    if (moduleMethods.length > 0) {
        for (const method of moduleMethods) {
            // Validate method has required documentation
            validateMethod(method, moduleName);

            const params = method.params || [];
            const paramStr = params.map(p => p.name).join(', ');

            content += `
            <div class="method" id="${method.name}">
                <h3>${moduleName}.${method.name}(${paramStr})</h3>
                <p class="description">${method.description}</p>`;

            // Always show parameters section
            content += `
                <h4>Parameters</h4>`;

            if (params.length > 0) {
                content += `
                <ul class="params">`;

                for (const param of params) {
                    content += `
                    <li>
                        <code>${param.name}</code>
                        <span class="type">${formatType(param.type)}</span>
                        <p class="param-desc">${param.description}</p>
                    </li>`;
                }

                content += `
                </ul>`;
            } else {
                content += `
                <p>None</p>`;
            }

            // Always show returns section
            content += `
                <h4>Returns</h4>`;

            if (method.returns) {
                content += `
                <p>
                    <span class="type">${formatType(method.returns.type)}</span>
                     - ${method.returns.description}
                </p>`;
            } else {
                content += `
                <p>Nothing</p>`;
            }

            content += `
            </div>`;
        }
    } else {
        content += `
            <p>This module has no methods.</p>`;
    }

    content += `
        </div>`;

    const html = generatePage(moduleName, content, moduleName);
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

    let content = `
        <div class="page-header">
            <h1>${typeName}</h1>
            <p class="module-type">Type</p>
        </div>`;

    // Always show type description
    content += `
        <div class="section">
            <p class="type-description">${protocol.description}</p>
        </div>`;

    content += `
        <div class="section">`;

    // Always show properties section
    content += `
            <h2>Properties</h2>`;

    const properties = protocol.properties || [];
    if (properties.length > 0) {
        for (const prop of properties) {
            // Validate property has required documentation
            validateProperty(prop, typeName);

            // Extract type from signature
            const typeMatch = prop.signature.match(/var\s+\w+\s*:\s*([^{]+)/);
            const propType = typeMatch ? typeMatch[1].trim() : 'any';

            content += `
            <div class="property" id="${prop.name}">
                <h3>${prop.name}</h3>
                <p class="type">${formatType(propType)}</p>
                <p class="description">${prop.description}</p>
            </div>`;
        }
    } else {
        content += `
            <p>This type has no properties.</p>`;
    }

    // Always show methods section
    content += `
            <h2>Methods</h2>`;

    const methods = protocol.methods || [];
    const filteredMethods = methods.filter(m => m.name !== 'init' || isGlobal);

    if (filteredMethods.length > 0) {
        for (const method of filteredMethods) {
            // Validate method has required documentation
            validateMethod(method, typeName);

            const params = method.params || [];
            const paramStr = params.map(p => p.name).join(', ');
            const methodName = method.name === 'init' ? 'constructor' : method.name;
            // Check if it's a static method by looking at the signature
            const isStatic = method.signature && method.signature.includes('static func');

            content += `
            <div class="method" id="${methodName}">
                <h3>
                    ${isStatic ? `<span class="static-badge">static</span> ` : ''}
                    ${isStatic ? `${typeName}.` : ''}${methodName}(${paramStr})
                </h3>
                <p class="description">${method.description}</p>`;

            // Always show parameters section
            content += `
                <h4>Parameters</h4>`;

            if (params.length > 0) {
                content += `
                <ul class="params">`;

                for (const param of params) {
                    content += `
                    <li>
                        <code>${param.name}</code>
                        <span class="type">${formatType(param.type)}</span>
                        <p class="param-desc">${param.description}</p>
                    </li>`;
                }

                content += `
                </ul>`;
            } else {
                content += `
                <p>None</p>`;
            }

            // Always show returns section
            content += `
                <h4>Returns</h4>`;

            if (method.returns) {
                content += `
                <p>
                    <span class="type">${formatType(method.returns.type)}</span>
                     - ${method.returns.description}
                </p>`;
            } else {
                content += `
                <p>Nothing</p>`;
            }

            content += `
            </div>`;
        }
    } else {
        content += `
            <p>This type has no methods.</p>`;
    }

    content += `
        </div>`;

    const html = generatePage(typeName, content, typeName);
    const outputPath = path.join(OUTPUT_DIR, `${typeName}.html`);
    fs.writeFileSync(outputPath, html);
    console.log(`  ✓ Generated ${typeName}.html`);
}

/**
 * Generate index page
 */
function generateIndexPage(modules, types) {
    const content = `
        <div class="page-header">
            <h1>Hammerspoon 2 API Documentation</h1>
            <p>Welcome to the Hammerspoon 2 API documentation</p>
        </div>

        <div class="section">
            <h2>Modules</h2>
            <p>Modules are the main entry points for Hammerspoon functionality.</p>
            <div class="grid">
                ${modules.map(m => `
                <a href="${m.name}.html" class="card">
                    <h3>${m.name}</h3>
                    <p>${m.swiftProtocols} protocols, ${m.javascriptFunctions} functions</p>
                </a>
                `).join('')}
            </div>
        </div>

        <div class="section">
            <h2>Types</h2>
            <p>Types represent objects that can be created and manipulated in Hammerspoon.</p>
            <div class="grid">
                ${types.map(t => `
                <a href="${t}.html" class="card">
                    <h3>${t}</h3>
                </a>
                `).join('')}
            </div>
        </div>
    `;

    const html = generatePage('Home', content, 'index');
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
 * Main execution
 */
function main() {
    console.log('Generating Hammerspoon 2 HTML Documentation...\n');

    // Load templates
    loadTemplates();

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
        for (const protocol of moduleData.swift.protocols) {
            if (protocol.type === 'typedef') {
                const typeName = protocol.name.replace(/API$/, '');
                generateTypePage(typeName, protocol, false);
            }
        }
    }

    // Generate global type pages
    console.log('\nGenerating type pages:');
    const allTypes = [];
    if (index.types) {
        const typesPath = path.join(JSON_DIR, 'types.json');
        const typesData = JSON.parse(fs.readFileSync(typesPath, 'utf8'));

        for (const protocol of typesData.swift.protocols) {
            const typeName = protocol.name.replace(/(API|JSExports?)$/, '');
            allTypes.push(typeName);
            generateTypePage(typeName, protocol, true);
        }
    }

    // Collect all type names from modules too
    for (const module of index.modules) {
        const modulePath = path.join(JSON_DIR, `${module.name}.json`);
        const moduleData = JSON.parse(fs.readFileSync(modulePath, 'utf8'));

        for (const protocol of moduleData.swift.protocols) {
            if (protocol.type === 'typedef') {
                const typeName = protocol.name.replace(/API$/, '');
                if (!allTypes.includes(typeName)) {
                    allTypes.push(typeName);
                }
            }
        }
    }

    // Generate index page
    console.log('\nGenerating index and assets:');
    generateIndexPage(index.modules, allTypes);

    // Generate JavaScript and CSS
    generateJavaScript(index.modules, allTypes);
    generateCSS();

    console.log(`\n✅ HTML documentation generated successfully!`);
    console.log(`   Output directory: ${OUTPUT_DIR}`);
    console.log(`   Open docs/html/index.html in your browser`);
}

main();
