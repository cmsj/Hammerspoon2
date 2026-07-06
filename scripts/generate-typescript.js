#!/usr/bin/env node

/**
 * TypeScript Definition Generator for Hammerspoon 2
 *
 * Generates a hammerspoon.d.ts file from the extracted JSON documentation
 * This allows users to write their Hammerspoon configuration in TypeScript
 * with full autocomplete, type checking, and inline documentation.
 */

const fs = require('fs');
const path = require('path');

const JSON_DIR = path.join(__dirname, '..', 'docs', 'json');
const OUTPUT_FILE = path.join(__dirname, '..', 'docs', 'hammerspoon.d.ts');

/**
 * Find the index of the first colon at bracket-depth 0 within a string.
 * Returns -1 if no such colon exists (i.e. the string is an array type, not a dictionary).
 */
function findTopLevelColon(s) {
    let depth = 0;
    for (let i = 0; i < s.length; i++) {
        if (s[i] === '[') depth++;
        else if (s[i] === ']') depth--;
        else if (s[i] === ':' && depth === 0) return i;
    }
    return -1;
}

/**
 * Convert Swift type to TypeScript type.
 * Uses bracket-counting rather than regex so nested types like [[String: Any]] resolve correctly.
 * @param {string} swiftType - The Swift type to convert
 * @param {string|null} promiseType - If this is a JSPromise, the inner type from documentation
 */
function swiftTypeToTS(swiftType, promiseType = null) {
    if (!swiftType) return 'any';

    const s = swiftType.trim();

    const typeMap = {
        'String': 'string',
        'Int': 'number',
        'Double': 'number',
        'Float': 'number',
        'Bool': 'boolean',
        'TimeInterval': 'number',
        'UInt32': 'number',
        'NSNumber': 'number',
        'NSDate': 'Date',
        'Any': 'any',
        'Void': 'void'
    };

    // Handle JSFunction - convert to a callable type.
    // JSFunction? must be handled before the generic ?-stripper to fix precedence:
    // "(...args: any[]) => any | null" would be parsed by TS as a function returning
    // "any | null" rather than an optional function. We parenthesise to fix that.
    if (s === 'JSFunction?' || s === 'JSFunction') {
        const fnType = '(...args: any[]) => any';
        return s.endsWith('?') ? `(${fnType}) | null` : fnType;
    }

    // Handle JSPromise - convert to Promise<T>
    // JSPromise? -> Promise<T> (the ? is expected since promises can fail to create)
    if (s === 'JSPromise?' || s === 'JSPromise') {
        const innerType = promiseType ? swiftTypeToTS(promiseType) : 'any';
        return `Promise<${innerType}>`;
    }

    // Handle optionals — strip trailing ? and recurse.
    // Swift nil bridges to JS null (not undefined), so all optional types use | null.
    if (s.endsWith('?')) {
        return `${swiftTypeToTS(s.slice(0, -1))} | null`;
    }

    // Handle [T] arrays and [K: V] dictionaries.
    // Regex alone can't distinguish these when T is itself a dictionary (e.g. [[String: Any]]),
    // so we use bracket-counting to find the key/value split at depth 0.
    if (s.startsWith('[') && s.endsWith(']')) {
        const inner = s.slice(1, -1).trim();
        const colonPos = findTopLevelColon(inner);
        if (colonPos !== -1) {
            const key = inner.slice(0, colonPos).trim();
            const value = inner.slice(colonPos + 1).trim();
            return `Record<${swiftTypeToTS(key)}, ${swiftTypeToTS(value)}>`;
        }
        return `${swiftTypeToTS(inner)}[]`;
    }

    return typeMap[s] || s;
}

/**
 * Resolve the TypeScript type for a parameter.
 * A {TypeScript type} annotation in the doc comment overrides the Swift-derived type.
 */
function resolveParamType(p, fromSwift = true) {
    if (p.tsType) return p.tsType;
    return fromSwift ? swiftTypeToTS(p.type) : p.type;
}

/**
 * Extract property type from Swift signature
 */
function extractPropertyType(signature) {
    const typeMatch = signature.match(/var\s+\w+\s*:\s*([^{]+)/);
    return typeMatch ? typeMatch[1].trim() : 'any';
}

/**
 * Returns true if the Swift property signature declares both get and set accessors
 */
function isWritableProperty(signature) {
    return signature.includes('get set');
}

/**
 * Escape special characters in documentation
 */
function escapeDocComment(text) {
    if (!text) return '';
    return text.replace(/\*\//g, '*\\/');
}

/**
 * Generate TypeScript definitions for a module
 */
function generateModuleDefinitions(moduleData) {
    let output = '';

    // Module namespace
    output += `/**\n`;
    if (moduleData.description) {
        output += ` * ${escapeDocComment(moduleData.description)}\n`;
    }
    output += ` */\n`;
    output += `declare namespace ${moduleData.name} {\n`;

    // Module methods
    for (const method of moduleData.methods || []) {
        output += `    /**\n`;
        if (method.description) {
            output += `     * ${escapeDocComment(method.description)}\n`;
        }
        if (method.params && method.params.length > 0) {
            for (const param of method.params) {
                const desc = param.description ? ` ${escapeDocComment(param.description)}` : '';
                output += `     * @param ${param.name}${desc}\n`;
            }
        }
        if (method.returns && method.returns.description) {
            output += `     * @returns ${escapeDocComment(method.returns.description)}\n`;
        }
        output += `     */\n`;

        // Method signature — p.optional maps to TypeScript's optional parameter (name?: type)
        const params = (method.params || []).map(p => {
            return `${p.name}${p.optional ? '?' : ''}: ${resolveParamType(p, method.source === 'swift')}`;
        }).join(', ');

        const returnType = method.returns
            ? (method.source === 'swift' ? swiftTypeToTS(method.returns.type, method.returns.promiseType) : method.returns.type)
            : 'void';

        output += `    function ${method.name}(${params}): ${returnType};\n\n`;
    }

    // Module properties
    for (const prop of moduleData.properties || []) {
        output += `    /**\n`;
        if (prop.description) {
            output += `     * ${escapeDocComment(prop.description)}\n`;
        }
        output += `     */\n`;

        const propType = prop.tsType || swiftTypeToTS(extractPropertyType(prop.signature));
        const keyword = isWritableProperty(prop.signature) ? 'let' : 'const';
        output += `    ${keyword} ${prop.name}: ${propType};\n\n`;
    }

    output += `}\n\n`;

    // Type definitions for this module
    for (const typeDef of moduleData.types || []) {
        output += generateTypeDefinition(typeDef);
    }

    return output;
}

/**
 * Generate TypeScript definitions for a type
 */
function generateTypeDefinition(protocol) {
    let output = '';
    const typeName = protocol.name.replace(/API$/, '');

    output += `/**\n`;
    if (protocol.description) {
        output += ` * ${escapeDocComment(protocol.description)}\n`;
    }
    output += ` */\n`;

    if (protocol.type === 'typedef') {
        // HSTypeAPI protocols: static methods as class, properties as interface
        output += `declare class ${typeName} {\n`;

        // Constructor if there's an init method
        const initMethod = (protocol.methods || []).find(m => m.name === 'init');
        if (initMethod) {
            output += `    /**\n`;
            if (initMethod.description) {
                output += `     * ${escapeDocComment(initMethod.description)}\n`;
            }
            for (const param of initMethod.params || []) {
                const desc = param.description ? ` ${escapeDocComment(param.description)}` : '';
                output += `     * @param ${param.name}${desc}\n`;
            }
            output += `     */\n`;

            const params = (initMethod.params || []).map(p => {
                return `${p.name}: ${resolveParamType(p)}`;
            }).join(', ');

            output += `    constructor(${params});\n\n`;
        }

        // Static methods
        for (const method of protocol.methods || []) {
            if (method.name === 'init') continue; // Already handled as constructor

            output += `    /**\n`;
            if (method.description) {
                output += `     * ${escapeDocComment(method.description)}\n`;
            }
            for (const param of method.params || []) {
                const desc = param.description ? ` ${escapeDocComment(param.description)}` : '';
                output += `     * @param ${param.name}${desc}\n`;
            }
            if (method.returns && method.returns.description) {
                output += `     * @returns ${escapeDocComment(method.returns.description)}\n`;
            }
            output += `     */\n`;

            const params = (method.params || []).map(p => {
                return `${p.name}${p.optional ? '?' : ''}: ${resolveParamType(p)}`;
            }).join(', ');

            const returnType = method.returns ? swiftTypeToTS(method.returns.type, method.returns.promiseType) : 'void';
            const staticPrefix = method.isStatic ? 'static ' : '';

            output += `    ${staticPrefix}${method.name}(${params}): ${returnType};\n\n`;
        }

        // Properties as instance members
        for (const prop of protocol.properties || []) {
            output += `    /**\n`;
            if (prop.description) {
                output += `     * ${escapeDocComment(prop.description)}\n`;
            }
            output += `     */\n`;
            const propType = prop.tsType || swiftTypeToTS(extractPropertyType(prop.signature));
            const readonlyPrefix = isWritableProperty(prop.signature) ? '' : 'readonly ';
            output += `    ${readonlyPrefix}${prop.name}: ${propType};\n\n`;
        }

        output += `}\n\n`;
    } else {
        // Regular class with instance methods
        output += `declare class ${typeName} {\n`;

        // Constructor
        const initMethod = (protocol.methods || []).find(m => m.name === 'init');
        if (initMethod) {
            output += `    /**\n`;
            if (initMethod.description) {
                output += `     * ${escapeDocComment(initMethod.description)}\n`;
            }
            for (const param of initMethod.params || []) {
                const desc = param.description ? ` ${escapeDocComment(param.description)}` : '';
                output += `     * @param ${param.name}${desc}\n`;
            }
            output += `     */\n`;

            const params = (initMethod.params || []).map(p => {
                return `${p.name}: ${resolveParamType(p)}`;
            }).join(', ');

            output += `    constructor(${params});\n\n`;
        }

        // Properties
        for (const prop of protocol.properties || []) {
            output += `    /**\n`;
            if (prop.description) {
                output += `     * ${escapeDocComment(prop.description)}\n`;
            }
            output += `     */\n`;
            const propType = prop.tsType || swiftTypeToTS(extractPropertyType(prop.signature));
            const readonlyPrefix = isWritableProperty(prop.signature) ? '' : 'readonly ';
            output += `    ${readonlyPrefix}${prop.name}: ${propType};\n\n`;
        }

        // Methods
        for (const method of protocol.methods || []) {
            if (method.name === 'init') continue; // Already handled

            output += `    /**\n`;
            if (method.description) {
                output += `     * ${escapeDocComment(method.description)}\n`;
            }
            for (const param of method.params || []) {
                const desc = param.description ? ` ${escapeDocComment(param.description)}` : '';
                output += `     * @param ${param.name}${desc}\n`;
            }
            if (method.returns && method.returns.description) {
                output += `     * @returns ${escapeDocComment(method.returns.description)}\n`;
            }
            output += `     */\n`;

            const params = (method.params || []).map(p => {
                return `${p.name}${p.optional ? '?' : ''}: ${resolveParamType(p)}`;
            }).join(', ');

            const returnType = method.returns ? swiftTypeToTS(method.returns.type, method.returns.promiseType) : 'void';

            output += `    ${method.name}(${params}): ${returnType};\n\n`;
        }

        output += `}\n\n`;
    }

    return output;
}

/**
 * Main execution
 */
function main() {
    console.log('Generating TypeScript definitions for Hammerspoon 2...\n');

    // Load index
    const indexPath = path.join(JSON_DIR, 'index.json');
    const index = JSON.parse(fs.readFileSync(indexPath, 'utf8'));

    let output = '';

    // Header
    output += `// TypeScript definitions for Hammerspoon 2\n`;
    output += `// Auto-generated from API documentation\n`;
    output += `// DO NOT EDIT - Regenerate using: npm run docs:typescript\n\n`;

    // Global types first
    if (index.types) {
        const typesPath = path.join(JSON_DIR, 'types.json');
        const typesData = JSON.parse(fs.readFileSync(typesPath, 'utf8'));

        output += `// ========================================\n`;
        output += `// Global Types\n`;
        output += `// ========================================\n\n`;

        for (const protocol of typesData.types || []) {
            output += generateTypeDefinition(protocol);
        }
    }

    // Module definitions
    output += `// ========================================\n`;
    output += `// Modules\n`;
    output += `// ========================================\n\n`;

    for (const module of index.modules) {
        const modulePath = path.join(JSON_DIR, `${module.name}.json`);
        const moduleData = JSON.parse(fs.readFileSync(modulePath, 'utf8'));
        output += generateModuleDefinitions(moduleData);
    }

    // Write output file
    fs.writeFileSync(OUTPUT_FILE, output);
    console.log(`✅ TypeScript definitions generated successfully!`);
    console.log(`   Output: ${OUTPUT_FILE}`);
    console.log(`   Size: ${(output.length / 1024).toFixed(2)} KB`);
}

main();
