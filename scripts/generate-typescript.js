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
 * Convert Swift type to TypeScript type
 * @param {string} swiftType - The Swift type to convert
 * @param {string|null} promiseType - If this is a JSPromise, the inner type from documentation
 */
function swiftTypeToTS(swiftType, promiseType = null) {
    const typeMap = {
        'String': 'string',
        'Int': 'number',
        'Double': 'number',
        'Float': 'number',
        'Bool': 'boolean',
        'TimeInterval': 'number',
        'UInt32': 'number',
        'Any': 'any',
        'Void': 'void'
    };

    // Handle JSPromise - convert to Promise<T>
    // JSPromise? -> Promise<T> (the ? is expected since promises can fail to create)
    if (swiftType === 'JSPromise?' || swiftType === 'JSPromise') {
        const innerType = promiseType ? swiftTypeToTS(promiseType) : 'any';
        return `Promise<${innerType}>`;
    }

    // Handle arrays
    if (swiftType.match(/^\[([^\]:]+)\]$/)) {
        const inner = swiftType.match(/^\[([^\]:]+)\]$/)[1];
        return `${swiftTypeToTS(inner)}[]`;
    }

    // Handle dictionaries
    if (swiftType.match(/^\[([^:]+):\s*([^\]]+)\]$/)) {
        const match = swiftType.match(/^\[([^:]+):\s*([^\]]+)\]$/);
        return `Record<${swiftTypeToTS(match[1])}, ${swiftTypeToTS(match[2])}>`;
    }

    // Handle optionals - TypeScript uses | undefined
    if (swiftType.endsWith('?')) {
        const cleanType = swiftType.slice(0, -1);
        return `${swiftTypeToTS(cleanType)} | undefined`;
    }

    return typeMap[swiftType] || swiftType;
}

/**
 * Extract property type from Swift signature
 */
function extractPropertyType(signature) {
    const typeMatch = signature.match(/var\s+\w+\s*:\s*([^{]+)/);
    return typeMatch ? typeMatch[1].trim() : 'any';
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

        // Method signature
        const params = (method.params || []).map(p => {
            const tsType = method.source === 'swift' ? swiftTypeToTS(p.type) : p.type;
            return `${p.name}: ${tsType}`;
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

        const propType = swiftTypeToTS(extractPropertyType(prop.signature));
        // Properties are const in TypeScript (readonly)
        output += `    const ${prop.name}: ${propType};\n\n`;
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
                return `${p.name}: ${swiftTypeToTS(p.type)}`;
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
                return `${p.name}: ${swiftTypeToTS(p.type)}`;
            }).join(', ');

            const returnType = method.returns ? swiftTypeToTS(method.returns.type, method.returns.promiseType) : 'void';

            output += `    static ${method.name}(${params}): ${returnType};\n\n`;
        }

        // Properties as instance members
        for (const prop of protocol.properties || []) {
            output += `    /**\n`;
            if (prop.description) {
                output += `     * ${escapeDocComment(prop.description)}\n`;
            }
            output += `     */\n`;
            const propType = swiftTypeToTS(extractPropertyType(prop.signature));
            output += `    ${prop.name}: ${propType};\n\n`;
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
                return `${p.name}: ${swiftTypeToTS(p.type)}`;
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
            const propType = swiftTypeToTS(extractPropertyType(prop.signature));
            output += `    ${prop.name}: ${propType};\n\n`;
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
                return `${p.name}: ${swiftTypeToTS(p.type)}`;
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
