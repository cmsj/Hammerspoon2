#!/usr/bin/env node

/**
 * Documentation Extraction Script for Hammerspoon 2
 * 
 * This script extracts API documentation from:
 * 1. Swift JSExport protocols (from .swift files)
 * 2. JSDoc comments (from .js files)
 * 
 * It combines the documentation by module and outputs:
 * - JSON files with structured API data
 * - Combined JavaScript files suitable for JSDoc HTML generation
 */

const fs = require('fs');
const path = require('path');

const MODULES_DIR = path.join(__dirname, '..', 'Hammerspoon 2', 'Modules');
const TYPES_DIR = path.join(__dirname, '..', 'Hammerspoon 2', 'Engine', 'Types');
const OUTPUT_JSON_DIR = path.join(__dirname, '..', 'docs', 'json');
const OUTPUT_COMBINED_DIR = path.join(OUTPUT_JSON_DIR, 'combined');

/**
 * Check if documentation contains SKIP_DOCS marker
 */
function shouldSkipDocs(docLines) {
    if (Array.isArray(docLines)) {
        return docLines.some(line => line.trim() === 'SKIP_DOCS');
    }
    return typeof docLines === 'string' && docLines.includes('SKIP_DOCS');
}

/**
 * Parse Swift file to extract JSExport protocol information
 */
function parseSwiftFile(filePath) {
    const content = fs.readFileSync(filePath, 'utf8');
    const protocols = [];
    let moduleDocumentation = null;
    
    // Find all @objc protocol definitions that extend JSExport or HSTypeAPI
    // We need to manually handle brace matching because protocols can have nested braces
    const protocolStartRegex = /@objc\s+protocol\s+(\w+)\s*:\s*([^{]+)\{/g;
    let match;
    let firstProtocolIndex = null;

    while ((match = protocolStartRegex.exec(content)) !== null) {
        // Track the first protocol for module-level documentation
        if (firstProtocolIndex === null) {
            firstProtocolIndex = match.index;
        }
        const protocolName = match[1];
        const inheritanceList = match[2].trim();

        // Only process protocols that extend JSExport or HSTypeAPI
        if (!inheritanceList.includes('JSExport') && !inheritanceList.includes('HSTypeAPI')) {
            continue;
        }

        // Extract protocol-level documentation (comments before @objc protocol)
        const beforeProtocol = content.substring(0, match.index);
        const beforeLines = beforeProtocol.split('\n');
        const protocolDoc = [];

        // Walk backwards from the protocol definition to collect /// comments
        for (let i = beforeLines.length - 1; i >= 0; i--) {
            const line = beforeLines[i].trim();
            if (line.startsWith('///')) {
                protocolDoc.unshift(line.replace(/^\/\/\/\s*/, ''));
            } else if (line && !line.startsWith('//')) {
                // Stop if we hit a non-comment, non-empty line
                break;
            }
        }

        const rawProtocolDoc = protocolDoc.join('\n');
        const protocolDescription = formatDocCToJSDoc(rawProtocolDoc);

        // Skip this protocol if it has SKIP_DOCS marker
        if (shouldSkipDocs(protocolDoc)) {
            continue;
        }

        // Find matching closing brace for the protocol
        let braceCount = 1;
        let pos = match.index + match[0].length;
        const bodyStart = pos;

        while (braceCount > 0 && pos < content.length) {
            if (content[pos] === '{') braceCount++;
            else if (content[pos] === '}') braceCount--;
            pos++;
        }

        const protocolBody = content.substring(bodyStart, pos - 1);

        // Check if this is a type definition (extends HSTypeAPI)
        const isType = inheritanceList.includes('HSTypeAPI');

        const protocol = {
            name: protocolName,
            type: isType ? 'typedef' : 'protocol',
            rawDocumentation: rawProtocolDoc,
            description: protocolDescription,
            methods: [],
            properties: []
        };
        
        // Extract doc comments and method/property signatures
        const lines = protocolBody.split('\n');
        let currentDoc = [];
        let pendingObjcSelector = false;  // Track if we saw @objc(selector) on previous line

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();

            // Collect documentation comments
            if (line.startsWith('///')) {
                currentDoc.push(line.replace(/^\/\/\/\s*/, ''));
                continue;
            }

            // Skip empty lines and single-line comments
            if (!line || line.startsWith('//')) {
                continue;
            }

            // Check for @objc with custom selector on its own line (e.g., @objc(doAt::::))
            if (line.match(/^@objc\([^)]+\)$/) && !line.includes('func') && !line.includes('var')) {
                pendingObjcSelector = true;
                continue;
            }

            // Parse methods and properties
            // Match @objc func/var, bare func/var (for protocol declarations), or func after @objc(selector)
            let methodMatch = null;

            if (line.startsWith('@objc')) {
                // @objc func or @objc var
                methodMatch = line.match(/@objc(?:\([^)]*\))?\s+(?:(?:static\s+)?func\s+(\w+)|var\s+(\w+))/);
            } else if (pendingObjcSelector && line.startsWith('func ')) {
                // This is a func following @objc(selector) on the previous line
                methodMatch = line.match(/func\s+(\w+)/);
                if (methodMatch) {
                    // Reformat to look like a normal @objc match result
                    methodMatch = [line, methodMatch[1], undefined];
                }
            } else if (line.match(/^(?:static\s+)?func\s+\w+/) || line.match(/^var\s+\w+/)) {
                // Bare function or property declaration in protocol (no @objc needed)
                methodMatch = line.match(/^(?:static\s+)?func\s+(\w+)|^var\s+(\w+)/);
            } else if (line.match(/^init\(/)) {
                // Constructor/initializer
                methodMatch = ['init', 'init', undefined];
            }

            pendingObjcSelector = false;  // Reset after processing
            
            if (methodMatch) {
                if (methodMatch[1]) {
                    // It's a method
                    const methodName = methodMatch[1];
                    let fullSignature = line;
                    
                    // Handle multi-line method signatures - look for the closing )
                    let j = i;
                    let parenDepth = 0;
                    let foundStart = false;
                    
                    // Count parentheses to find the end of the method signature
                    for (let k = 0; k < line.length; k++) {
                        if (line[k] === '(') {
                            parenDepth++;
                            foundStart = true;
                        } else if (line[k] === ')') {
                            parenDepth--;
                        }
                    }
                    
                    // Continue reading lines if we haven't closed all parentheses
                    while (foundStart && parenDepth > 0 && j + 1 < lines.length) {
                        j++;
                        const nextLine = lines[j].trim();
                        fullSignature += ' ' + nextLine;
                        
                        for (let k = 0; k < nextLine.length; k++) {
                            if (nextLine[k] === '(') parenDepth++;
                            else if (nextLine[k] === ')') parenDepth--;
                        }
                    }
                    
                    // If there's a return type arrow, capture up to the return type
                    // Check if the signature already looks complete (has -> followed by a type)
                    const hasCompleteReturn = fullSignature.match(/->\s*\w+(\?|\])?(\s|$)/);

                    if (fullSignature.includes('->') && !hasCompleteReturn) {
                        // Continue until we find a type that ends the signature
                        while (j + 1 < lines.length) {
                            const nextLine = lines[j + 1].trim();
                            // Stop if we hit another @objc or empty line
                            if (nextLine.startsWith('@objc') || nextLine.startsWith('///') || !nextLine) {
                                break;
                            }
                            // Stop if the line seems to be starting a new declaration
                            if (nextLine.match(/^(var|func|@|static)/)) {
                                break;
                            }
                            j++;
                            fullSignature += ' ' + nextLine;
                            // If we hit a complete type (ends with something like ']' or '?' or a word)
                            if (nextLine.match(/[\w\?\]\>]$/)) {
                                break;
                            }
                        }
                    }
                    
                    // Clean up the signature - remove @objc but keep static
                    fullSignature = fullSignature.replace(/@objc(?:\([^)]*\))?\s*/, '').trim();

                    // Try to extract just the function signature without trailing junk
                    // Stop at the next function/variable declaration
                    const cleanSigMatch = fullSignature.match(/((?:static\s+)?func\s+\w+.*?->\s*\S+?)(?=\s+(?:static\s+)?(?:func|var)|$)/);
                    if (cleanSigMatch) {
                        fullSignature = cleanSigMatch[1].trim();
                    } else {
                        // Try without return type (for functions without return values)
                        const noReturnMatch = fullSignature.match(/((?:static\s+)?func\s+\w+\s*\([^)]*\))(?=\s+(?:static\s+)?(?:func|var)|$)/);
                        if (noReturnMatch) {
                            fullSignature = noReturnMatch[1].trim();
                        }
                    }
                    
                    const rawDoc = currentDoc.join('\n');

                    // Skip this method if it has SKIP_DOCS marker
                    if (!shouldSkipDocs(currentDoc)) {
                        protocol.methods.push({
                            name: methodName,
                            signature: fullSignature,
                            rawDocumentation: rawDoc,
                            description: formatDocCToJSDoc(rawDoc),
                            params: extractParams(fullSignature, currentDoc),
                            returns: extractReturns(fullSignature, currentDoc)
                        });
                    }

                    // Move i forward if we read multiple lines
                    i = j;
                } else if (methodMatch[2]) {
                    // It's a property
                    const propName = methodMatch[2];
                    const rawDoc = currentDoc.join('\n');

                    // Skip this property if it has SKIP_DOCS marker
                    if (!shouldSkipDocs(currentDoc)) {
                        protocol.properties.push({
                            name: propName,
                            signature: line.replace(/@objc\s*/, ''),
                            rawDocumentation: rawDoc,
                            description: formatDocCToJSDoc(rawDoc)
                        });
                    }
                }
                currentDoc = [];
            }
        }
        
        protocols.push(protocol);
    }

    // Extract module-level documentation (before the first protocol)
    if (firstProtocolIndex !== null) {
        const beforeFirstProtocol = content.substring(0, firstProtocolIndex);
        const lines = beforeFirstProtocol.split('\n');
        const moduleDoc = [];

        // Walk backwards from the first protocol to collect /// comments
        // Stop when we hit imports or other non-doc content
        for (let i = lines.length - 1; i >= 0; i--) {
            const line = lines[i].trim();
            if (line.startsWith('///')) {
                moduleDoc.unshift(line.replace(/^\/\/\/\s*/, ''));
            } else if (line && !line.startsWith('//')) {
                // Stop if we hit a non-comment, non-empty line
                break;
            }
        }

        if (moduleDoc.length > 0) {
            const rawModuleDoc = moduleDoc.join('\n');
            moduleDocumentation = {
                rawDocumentation: rawModuleDoc,
                description: formatDocCToJSDoc(rawModuleDoc)
            };
        }
    }

    return { protocols, moduleDocumentation };
}

/**
 * Extract parameter descriptions from documentation
 */
function extractParamDescriptions(docLines) {
    const descriptions = {};
    let inParams = false;

    for (const line of docLines) {
        const trimmed = line.trim();

        // Check for Parameters section (with or without leading dash)
        if (trimmed === '- Parameters:' || trimmed === '- Parameters' ||
            trimmed === 'Parameters:' || trimmed === 'Parameters') {
            inParams = true;
            continue;
        }

        // Check for single Parameter (with or without leading dash)
        const singleParamMatch = trimmed.match(/^-?\s*Parameter\s+(\w+)\s*:\s*(.+)$/);
        if (singleParamMatch) {
            descriptions[singleParamMatch[1]] = singleParamMatch[2].trim();
            continue;
        }

        // If we're in Parameters section, look for individual parameters
        if (inParams) {
            const paramMatch = trimmed.match(/^-\s+(\w+)\s*:\s*(.+)$/);
            if (paramMatch) {
                descriptions[paramMatch[1]] = paramMatch[2].trim();
                continue;
            }
            // Stop if we hit a non-parameter line or Returns section
            if ((trimmed.startsWith('- ') && !trimmed.match(/^-\s+\w+\s*:/)) ||
                trimmed.startsWith('Returns:') || trimmed.startsWith('- Returns:')) {
                inParams = false;
            }
        }
    }

    return descriptions;
}

/**
 * Extract parameters from a Swift function signature and documentation
 */
function extractParams(signature, docLines = []) {
    const params = [];
    // Match both func and init signatures
    const funcMatch = signature.match(/(?:func\s+\w+|init)\s*\(([^)]*)\)/);
    if (!funcMatch) return params;

    const paramsStr = funcMatch[1];
    if (!paramsStr.trim()) return params;

    // Extract parameter descriptions from documentation
    const descriptions = extractParamDescriptions(docLines);

    // Split by comma, but be careful of nested generics/closures
    const parts = splitParams(paramsStr);

    for (const part of parts) {
        const paramMatch = part.match(/(?:_\s+)?(\w+)\s*:\s*([^=]+)/);
        if (paramMatch) {
            const paramName = paramMatch[1];
            params.push({
                name: paramName,
                type: paramMatch[2].trim(),
                description: descriptions[paramName] || ''
            });
        }
    }

    return params;
}

/**
 * Split parameter string by commas, respecting nested structures
 */
function splitParams(str) {
    const parts = [];
    let current = '';
    let depth = 0;
    
    for (let i = 0; i < str.length; i++) {
        const char = str[i];
        if (char === '(' || char === '[' || char === '<') {
            depth++;
        } else if (char === ')' || char === ']' || char === '>') {
            depth--;
        } else if (char === ',' && depth === 0) {
            parts.push(current.trim());
            current = '';
            continue;
        }
        current += char;
    }
    
    if (current.trim()) {
        parts.push(current.trim());
    }
    
    return parts;
}

/**
 * Extract property type from Swift property signature
 */
function extractPropertyType(signature) {
    // Match: var propertyName: Type { get } or var propertyName: Type { get set }
    const typeMatch = signature.match(/var\s+\w+\s*:\s*([^{]+)/);
    if (typeMatch) {
        return typeMatch[1].trim();
    }
    return '*'; // Default to any type if we can't parse it
}

/**
 * Extract return type from Swift function signature
 */
function extractReturns(signature, docLines) {
    // Match return type - handle arrays, dictionaries, optionals, and complex types
    // Matches: -> Type, -> [Type], -> [Key: Value], -> Type?
    const returnMatch = signature.match(/->\s*(.+?)(?=\s*(?:@|$|\/\/|\{))/);
    if (returnMatch) {
        // Look for return description in documentation
        let returnDesc = '';
        for (const line of docLines) {
            const trimmed = line.trim();
            // Match both "Returns:" and "- Returns:"
            const descMatch = trimmed.match(/^-?\s*Returns?\s*:\s*(.+)$/);
            if (descMatch) {
                returnDesc = descMatch[1].trim();
                break;
            }
        }

        return {
            type: returnMatch[1].trim(),
            description: returnDesc
        };
    }
    return null;
}

/**
 * Parse JavaScript file to extract JSDoc comments and function definitions
 */
function parseJavaScriptFile(filePath, moduleName = null) {
    const content = fs.readFileSync(filePath, 'utf8');
    const functions = [];

    // Helper to strip module prefix from function names
    const stripModulePrefix = (name) => {
        if (moduleName && name.startsWith(moduleName + '.')) {
            return name.substring(moduleName.length + 1);
        }
        return name;
    };

    // Match JSDoc comments followed by function definitions
    const jsdocRegex = /\/\*\*([^*]*(?:\*(?!\/)[^*]*)*)\*\/\s*(?:(\w+(?:\.\w+)*)\s*=\s*function\s*\(([^)]*)\)|function\s+(\w+)\s*\(([^)]*)\))/g;
    let match;

    while ((match = jsdocRegex.exec(content)) !== null) {
        const docComment = match[1];
        const functionName = match[2] || match[4];
        const params = match[3] || match[5];

        if (functionName) {
            const parsed = parseJSDoc(docComment);
            functions.push({
                name: stripModulePrefix(functionName),
                rawDocumentation: docComment.trim(),
                description: parsed.description,
                params: parsed.params,
                returns: parsed.returns,
                type: 'function'
            });
        }
    }

    // Also match Swift-style /// comments followed by function definitions
    const lines = content.split('\n');
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];

        // Check if this line is a function definition
        const funcMatch = line.match(/(\w+(?:\.\w+)*)\s*=\s*function\s*\(([^)]*)\)/);
        if (funcMatch) {
            const functionName = funcMatch[1];
            const params = funcMatch[2];

            // Check if already captured by JSDoc regex
            if (functions.find(f => f.name === functionName)) {
                continue;
            }

            // Look backwards for /// comments
            const docLines = [];
            for (let j = i - 1; j >= 0; j--) {
                const prevLine = lines[j].trim();
                if (prevLine.startsWith('///')) {
                    docLines.unshift(prevLine.replace(/^\/\/\/\s*/, ''));
                } else if (prevLine && !prevLine.startsWith('//')) {
                    break;
                }
            }

            if (docLines.length > 0) {
                const docText = docLines.join('\n');
                const parsed = parseDocCStyleComment(docText);
                functions.push({
                    name: stripModulePrefix(functionName),
                    rawDocumentation: docText,
                    description: formatDocCToJSDoc(docText),
                    params: parsed.params,
                    returns: parsed.returns,
                    type: 'function'
                });
            }
        }
    }
    
    // Also match simple assignments without JSDoc (for coverage)
    const simpleRegex = /(?:^|\n)(?!\/\*\*)(\w+(?:\.\w+)*)\s*=\s*function\s*\(([^)]*)\)/g;
    while ((match = simpleRegex.exec(content)) !== null) {
        const functionName = match[1];
        const params = match[2];
        const strippedName = stripModulePrefix(functionName);

        // Only add if not already captured by JSDoc regex
        if (!functions.find(f => f.name === strippedName)) {
            functions.push({
                name: strippedName,
                rawDocumentation: '',
                description: '',
                params: params.split(',').map(p => p.trim()).filter(p => p).map(name => ({
                    name: name,
                    type: 'any',
                    description: ''
                })),
                returns: null,
                type: 'function'
            });
        }
    }

    return functions;
}

/**
 * Parse DocC-style comment (used in Swift and some JavaScript files)
 */
function parseDocCStyleComment(docText) {
    const lines = docText.split('\n').map(line => line.trim());
    const descriptions = extractParamDescriptions(lines);

    const doc = {
        description: '',
        params: [],
        returns: null
    };

    // Extract main description (lines before Parameters/Returns)
    const descLines = [];
    for (const line of lines) {
        if (line.startsWith('- Parameter') || line.startsWith('- Parameters') || line.startsWith('- Returns') ||
            line.startsWith('Parameter') || line.startsWith('Parameters') || line.startsWith('Returns')) {
            break;
        }
        descLines.push(line);
    }
    doc.description = descLines.join(' ').trim();

    // Extract parameters - they're in the descriptions map
    for (const [paramName, paramDesc] of Object.entries(descriptions)) {
        doc.params.push({
            name: paramName,
            type: 'any',
            description: paramDesc
        });
    }

    // Extract returns (with or without leading dash)
    const returnsMatch = docText.match(/-?\s*Returns?:\s*(.+)/);
    if (returnsMatch) {
        doc.returns = {
            type: 'any',
            description: returnsMatch[1].trim()
        };
    }

    return doc;
}

/**
 * Parse JSDoc comment into structured data
 */
function parseJSDoc(docText) {
    const lines = docText.split('\n').map(line => line.replace(/^\s*\*\s?/, '').trim());
    
    const doc = {
        description: '',
        params: [],
        returns: null,
        examples: []
    };
    
    let currentSection = 'description';
    let descLines = [];
    
    for (const line of lines) {
        if (line.startsWith('@param')) {
            currentSection = 'param';
            const paramMatch = line.match(/@param\s+(?:\{([^}]+)\}\s+)?(\w+)\s*(.*)/);
            if (paramMatch) {
                doc.params.push({
                    name: paramMatch[2],
                    type: paramMatch[1] || 'any',
                    description: paramMatch[3]
                });
            }
        } else if (line.startsWith('@returns') || line.startsWith('@return')) {
            currentSection = 'returns';
            const returnMatch = line.match(/@returns?\s+(?:\{([^}]+)\}\s+)?(.*)/);
            if (returnMatch) {
                doc.returns = {
                    type: returnMatch[1] || 'any',
                    description: returnMatch[2]
                };
            }
        } else if (line.startsWith('@example')) {
            currentSection = 'example';
        } else if (currentSection === 'description' && line) {
            descLines.push(line);
        } else if (currentSection === 'example' && line) {
            doc.examples.push(line);
        }
    }
    
    doc.description = descLines.join(' ');
    
    return doc;
}

/**
 * Convert Swift type to JSDoc-compatible type
 */
function swiftTypeToJSDoc(swiftType) {
    // Remove optional marker
    let type = swiftType.replace(/\?$/, '');
    
    // Convert Swift array syntax to JSDoc array syntax
    // [Type] -> Array<Type>
    const arrayMatch = type.match(/^\[([^\]:]+)\]$/);
    if (arrayMatch) {
        return `Array<${arrayMatch[1]}>`;
    }
    
    // Convert Swift dictionary syntax if needed
    // [Key: Value] -> Object<Key, Value>
    const dictMatch = type.match(/^\[([^:]+):\s*([^\]]+)\]$/);
    if (dictMatch) {
        return `Object<${dictMatch[1].trim()}, ${dictMatch[2].trim()}>`;
    }
    
    // Map common Swift types to JS types
    const typeMap = {
        'String': 'string',
        'Int': 'number',
        'Double': 'number',
        'Float': 'number',
        'Bool': 'boolean',
        'TimeInterval': 'number',
        'UInt32': 'number',
        'Any': '*'
    };
    
    return typeMap[type] || type;
}

/**
 * Escape JavaScript keywords in function names
 */
function escapeFunctionName(name) {
    const keywords = ['new', 'delete', 'default', 'function', 'class', 'var', 'let', 'const'];
    if (keywords.includes(name)) {
        return `_${name}`;
    }
    return name;
}

/**
 * Process a module directory
 */
function processModule(moduleName, modulePath) {
    console.log(`Processing module: ${moduleName}`);

    const moduleData = {
        name: moduleName,
        swift: {
            protocols: [],
            objects: []
        },
        javascript: {
            functions: []
        }
    };

    // Find all Swift and JavaScript files in the module directory
    const files = fs.readdirSync(modulePath);
    let collectedModuleDoc = null;

    for (const file of files) {
        const filePath = path.join(modulePath, file);

        if (file.endsWith('.swift')) {
            const { protocols, moduleDocumentation } = parseSwiftFile(filePath);

            // Collect module-level documentation (prefer from Module.swift files)
            if (moduleDocumentation && !collectedModuleDoc) {
                collectedModuleDoc = moduleDocumentation;
            } else if (moduleDocumentation && file.includes('Module.swift')) {
                // Override with Module.swift documentation if we find it
                collectedModuleDoc = moduleDocumentation;
            }

            // Categorize as Module or Object based on naming convention
            if (file.includes('Module.swift')) {
                moduleData.swift.protocols.push(...protocols.map(p => ({ ...p, category: 'module' })));
            } else if (file.includes('Object.swift')) {
                moduleData.swift.protocols.push(...protocols.map(p => ({ ...p, category: 'object' })));
            } else {
                moduleData.swift.protocols.push(...protocols);
            }
        } else if (file.endsWith('.js')) {
            const functions = parseJavaScriptFile(filePath, moduleName);
            moduleData.javascript.functions.push(...functions);
        }
    }

    // Add module-level documentation if we found any
    if (collectedModuleDoc) {
        moduleData.description = collectedModuleDoc.description;
        moduleData.rawDocumentation = collectedModuleDoc.rawDocumentation;
    }

    return moduleData;
}

/**
 * Process the Engine/Types directory
 */
function processTypes(typesPath) {
    console.log('Processing types from Engine/Types');

    const typesData = {
        name: 'Types',
        swift: {
            protocols: []
        }
    };

    // Find all Swift files in the types directory
    const files = fs.readdirSync(typesPath).filter(f => f.endsWith('.swift'));

    for (const file of files) {
        const filePath = path.join(typesPath, file);
        const { protocols } = parseSwiftFile(filePath);
        typesData.swift.protocols.push(...protocols.map(p => ({ ...p, category: 'type' })));
    }

    return typesData;
}

/**
 * Format DocC documentation to JSDoc format
 * Converts Apple's DocC format (- Parameters:, - Returns:) to clean descriptions
 */
function formatDocCToJSDoc(documentation) {
    if (!documentation) return '';

    const lines = documentation.split('\n');
    const result = [];
    let inParamsList = false;

    for (const line of lines) {
        const trimmed = line.trim();

        // Skip parameter list headers (with or without leading dash)
        if (trimmed === '- Parameters:' || trimmed.startsWith('- Parameters:') ||
            trimmed === 'Parameters:' || trimmed.startsWith('Parameters:')) {
            inParamsList = true;
            continue;
        }

        // Skip returns line (with or without leading dash)
        if (trimmed.startsWith('- Returns:') || trimmed.startsWith('Returns:')) {
            break;
        }

        // Skip individual parameter documentation (starts with "- paramName:")
        if (inParamsList && trimmed.match(/^-\s+\w+:/)) {
            continue;
        }

        // If we hit a non-parameter line, we're out of the params list
        if (inParamsList && !trimmed.startsWith('-')) {
            inParamsList = false;
        }

        // Skip Note: lines for now (could be added as @note in future)
        if (trimmed.startsWith('- Note:') || trimmed.startsWith('Note:')) {
            continue;
        }

        // Keep the main description line
        if (!trimmed.startsWith('-') && trimmed && !trimmed.endsWith(':')) {
            result.push(trimmed);
        }
    }

    return result.join(' ');
}

/**
 * Generate combined JSDoc-compatible file for a module
 */
function generateCombinedJSDoc(moduleData) {
    // Create namespace using bracket notation for names with dots
    const namespaceVar = moduleData.name.includes('.')
        ? `globalThis['${moduleData.name}']`
        : moduleData.name;

    let output = `/**\n * @namespace ${moduleData.name}\n */\n`;
    output += `${namespaceVar} = {};\n\n`;

    // First, generate @typedef for any type protocols (those extending HSTypeAPI)
    for (const protocol of moduleData.swift.protocols) {
        if (protocol.type === 'typedef') {
            // Extract the type name from the protocol name (e.g., HSAlertAPI -> HSAlert)
            // The actual type name should be the protocol name minus 'API' suffix
            const typeName = protocol.name.replace(/API$/, '');

            output += `/**\n`;
            output += ` * @typedef {Object} ${typeName}\n`;

            // Add property definitions
            for (const prop of protocol.properties) {
                const propType = swiftTypeToJSDoc(extractPropertyType(prop.signature));
                output += ` * @property {${propType}} ${prop.name}`;
                if (prop.description) {
                    output += ` - ${prop.description}`;
                }
                output += `\n`;
            }

            output += ` */\n\n`;
        }
    }

    // Add Swift protocol methods as JSDoc
    for (const protocol of moduleData.swift.protocols) {
        // Add methods (including those from typedef protocols)
        for (const method of protocol.methods) {
            const escapedName = escapeFunctionName(method.name);

            output += `/**\n`;
            if (method.description) {
                output += ` * ${method.description}\n`;
                output += ` *\n`;
            }
            for (const param of method.params) {
                output += ` * @param {${swiftTypeToJSDoc(param.type)}} ${param.name}\n`;
            }
            if (method.returns) {
                const returnDesc = method.returns.description || '';
                output += ` * @returns {${swiftTypeToJSDoc(method.returns.type)}}${returnDesc ? ' ' + returnDesc : ''}\n`;
            }
            output += ` */\n`;
            output += `${moduleData.name}.${escapedName} = function(${method.params.map(p => p.name).join(', ')}) {};\n\n`;
        }

        // Add properties (but skip properties from typedef protocols since they're in the @typedef)
        if (protocol.type !== 'typedef') {
            for (const prop of protocol.properties) {
                output += `/**\n`;
                if (prop.description) {
                    output += ` * ${prop.description}\n`;
                }
                output += ` * @type {*}\n`;
                output += ` */\n`;
                output += `${moduleData.name}.${prop.name};\n\n`;
            }
        }
    }

    // Add JavaScript functions
    for (const func of moduleData.javascript.functions) {
        output += `/**\n`;
        if (func.description) {
            output += ` * ${func.description}\n`;
            output += ` *\n`;
        }
        if (func.params && func.params.length > 0) {
            for (const param of func.params) {
                const desc = param.description ? ' ' + param.description : '';
                output += ` * @param {${param.type}} ${param.name}${desc}\n`;
            }
        }
        if (func.returns) {
            const desc = func.returns.description ? ' ' + func.returns.description : '';
            output += ` * @returns {${func.returns.type}}${desc}\n`;
        }
        output += ` */\n`;
        output += `${func.name} = function(${func.params.map(p => p.name).join(', ')}) {};\n\n`;
    }

    return output;
}

/**
 * Generate JSDoc-compatible file for global types (from Engine/Types)
 */
function generateTypesJSDoc(typesData) {
    let output = '// Global Type Definitions\n\n';

    for (const protocol of typesData.swift.protocols) {
        // Extract the class/type name from the protocol name
        // HSFontAPI -> HSFont, HSPointJSExports -> HSPoint
        const typeName = protocol.name.replace(/(API|JSExports?)$/, '');

        if (protocol.type === 'typedef') {
            // HSTypeAPI protocols: These have static methods and should be documented as classes
            output += `/**\n`;
            output += ` * @class ${typeName}\n`;
            output += ` */\n`;
            output += `class ${typeName} {}\n\n`;

            // Add static methods
            for (const method of protocol.methods) {
                const escapedName = escapeFunctionName(method.name);

                output += `/**\n`;
                if (method.description) {
                    output += ` * ${method.description}\n`;
                    output += ` *\n`;
                }
                for (const param of method.params) {
                    output += ` * @param {${swiftTypeToJSDoc(param.type)}} ${param.name}\n`;
                }
                if (method.returns) {
                    const returnDesc = method.returns.description || '';
                    output += ` * @returns {${swiftTypeToJSDoc(method.returns.type)}}${returnDesc ? ' ' + returnDesc : ''}\n`;
                }
                output += ` */\n`;
                output += `${typeName}.${escapedName} = function(${method.params.map(p => p.name).join(', ')}) {};\n\n`;
            }

            // Add properties as typedef if any
            if (protocol.properties.length > 0) {
                output += `/**\n`;
                output += ` * @typedef {Object} ${typeName}Instance\n`;
                for (const prop of protocol.properties) {
                    const propType = swiftTypeToJSDoc(extractPropertyType(prop.signature));
                    output += ` * @property {${propType}} ${prop.name}`;
                    if (prop.description) {
                        output += ` - ${prop.description}`;
                    }
                    output += `\n`;
                }
                output += ` */\n\n`;
            }
        } else {
            // Regular JSExport protocols: These are instance classes with constructors
            output += `/**\n`;
            output += ` * @class ${typeName}\n`;

            // Add properties to the class documentation
            for (const prop of protocol.properties) {
                const propType = swiftTypeToJSDoc(extractPropertyType(prop.signature));
                output += ` * @property {${propType}} ${prop.name}`;
                if (prop.description) {
                    output += ` - ${prop.description}`;
                }
                output += `\n`;
            }
            output += ` */\n`;
            output += `class ${typeName} {\n`;

            // Add constructor if there are methods (look for init)
            const initMethod = protocol.methods.find(m => m.name === 'init');
            if (initMethod) {
                output += `    /**\n`;
                if (initMethod.description) {
                    output += `     * ${initMethod.description}\n`;
                    output += `     *\n`;
                }
                for (const param of initMethod.params) {
                    output += `     * @param {${swiftTypeToJSDoc(param.type)}} ${param.name}\n`;
                }
                output += `     */\n`;
                output += `    constructor(${initMethod.params.map(p => p.name).join(', ')}) {}\n\n`;
            }

            // Add other methods
            for (const method of protocol.methods) {
                if (method.name === 'init') continue; // Skip init, already handled as constructor

                const escapedName = escapeFunctionName(method.name);

                output += `    /**\n`;
                if (method.description) {
                    output += `     * ${method.description}\n`;
                    output += `     *\n`;
                }
                for (const param of method.params) {
                    output += `     * @param {${swiftTypeToJSDoc(param.type)}} ${param.name}\n`;
                }
                if (method.returns) {
                    const returnDesc = method.returns.description || '';
                    output += `     * @returns {${swiftTypeToJSDoc(method.returns.type)}}${returnDesc ? ' ' + returnDesc : ''}\n`;
                }
                output += `     */\n`;
                output += `    ${escapedName}(${method.params.map(p => p.name).join(', ')}) {}\n\n`;
            }

            output += `}\n\n`;
        }
    }

    return output;
}

/**
 * Main execution
 */
function main() {
    console.log('Extracting Hammerspoon 2 API Documentation...\n');

    // Ensure output directories exist
    if (!fs.existsSync(OUTPUT_JSON_DIR)) {
        fs.mkdirSync(OUTPUT_JSON_DIR, { recursive: true });
    }
    if (!fs.existsSync(OUTPUT_COMBINED_DIR)) {
        fs.mkdirSync(OUTPUT_COMBINED_DIR, { recursive: true });
    }

    // Find all module directories
    const moduleDirs = fs.readdirSync(MODULES_DIR)
        .filter(name => name.startsWith('hs.'))
        .filter(name => fs.statSync(path.join(MODULES_DIR, name)).isDirectory());

    const allModules = [];

    for (const moduleName of moduleDirs) {
        const modulePath = path.join(MODULES_DIR, moduleName);
        const moduleData = processModule(moduleName, modulePath);

        allModules.push(moduleData);

        // Save individual module JSON
        const jsonPath = path.join(OUTPUT_JSON_DIR, `${moduleName}.json`);
        fs.writeFileSync(jsonPath, JSON.stringify(moduleData, null, 2));
        console.log(`  ✓ Saved JSON: ${jsonPath}`);

        // Save combined JSDoc file
        const combinedJSDoc = generateCombinedJSDoc(moduleData);
        const combinedPath = path.join(OUTPUT_COMBINED_DIR, `${moduleName}.js`);
        fs.writeFileSync(combinedPath, combinedJSDoc);
        console.log(`  ✓ Saved combined: ${combinedPath}`);
    }

    // Process Engine/Types directory if it exists
    let typesData = null;
    if (fs.existsSync(TYPES_DIR)) {
        console.log('\n'); // Add spacing
        typesData = processTypes(TYPES_DIR);

        // Save types JSON
        const typesJsonPath = path.join(OUTPUT_JSON_DIR, 'types.json');
        fs.writeFileSync(typesJsonPath, JSON.stringify(typesData, null, 2));
        console.log(`  ✓ Saved JSON: ${typesJsonPath}`);

        // Save combined types JSDoc file
        const typesJSDoc = generateTypesJSDoc(typesData);
        const typesCombinedPath = path.join(OUTPUT_COMBINED_DIR, 'types.js');
        fs.writeFileSync(typesCombinedPath, typesJSDoc);
        console.log(`  ✓ Saved combined: ${typesCombinedPath}`);
    }

    // Save index of all modules and types
    const indexPath = path.join(OUTPUT_JSON_DIR, 'index.json');
    const indexData = {
        modules: allModules.map(m => ({
            name: m.name,
            swiftProtocols: m.swift.protocols.length,
            javascriptFunctions: m.javascript.functions.length
        })),
        generatedAt: new Date().toISOString()
    };

    if (typesData) {
        indexData.types = {
            count: typesData.swift.protocols.length,
            protocols: typesData.swift.protocols.map(p => p.name)
        };
    }

    fs.writeFileSync(indexPath, JSON.stringify(indexData, null, 2));
    console.log(`\n✓ Saved module index: ${indexPath}`);

    console.log(`\n✅ Documentation extraction complete!`);
    console.log(`   - Processed ${allModules.length} modules`);
    if (typesData) {
        console.log(`   - Processed ${typesData.swift.protocols.length} types`);
    }
    console.log(`   - JSON files: docs/json/`);
    console.log(`   - Combined JSDoc: docs/json/combined/`);
}

main();
