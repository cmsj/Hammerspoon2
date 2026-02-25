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

const REPO_ROOT = path.join(__dirname, '..');
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
function parseSwiftFile(filePath, repoRoot) {
    const content = fs.readFileSync(filePath, 'utf8');
    const protocols = [];
    let moduleDocumentation = null;

    // Calculate relative path from repo root
    const relativePath = path.relative(repoRoot, filePath);

    // Helper to get line number from character position
    const getLineNumber = (charPos) => {
        return content.substring(0, charPos).split('\n').length;
    };

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
        let charOffset = bodyStart;  // Track character position in original content

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            const lineStartPos = charOffset;
            charOffset += lines[i].length + 1; // +1 for newline

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
                            returns: extractReturns(fullSignature, currentDoc),
                            source: 'swift',
                            filePath: relativePath,
                            lineNumber: getLineNumber(lineStartPos)
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
                            description: formatDocCToJSDoc(rawDoc),
                            source: 'swift',
                            filePath: relativePath,
                            lineNumber: getLineNumber(lineStartPos)
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
 * Supports JSDoc-style type annotations in documentation: {Promise<Type>}
 */
function extractReturns(signature, docLines) {
    // Match return type - handle arrays, dictionaries, optionals, and complex types
    // Matches: -> Type, -> [Type], -> [Key: Value], -> Type?
    const returnMatch = signature.match(/->\s*(.+?)(?=\s*(?:@|$|\/\/|\{))/);
    if (returnMatch) {
        // Look for return description in documentation
        let returnDesc = '';
        let promiseType = null;

        for (const line of docLines) {
            const trimmed = line.trim();
            // Match both "Returns:" and "- Returns:" with optional {Type} annotation
            // Format: "- Returns: {Promise<boolean>} A promise that resolves to..."
            const descMatch = trimmed.match(/^-?\s*Returns?\s*:\s*(?:\{([^}]+)\}\s+)?(.*)$/);
            if (descMatch) {
                const typeAnnotation = descMatch[1];
                returnDesc = descMatch[2].trim();

                // Check if there's a Promise type annotation
                if (typeAnnotation) {
                    const promiseMatch = typeAnnotation.match(/^Promise<(.+)>$/);
                    if (promiseMatch) {
                        promiseType = promiseMatch[1];
                    }
                }
                break;
            }
        }

        const result = {
            type: returnMatch[1].trim(),
            description: returnDesc
        };

        // Add promiseType if we found one in the documentation
        if (promiseType) {
            result.promiseType = promiseType;
        }

        return result;
    }
    return null;
}

/**
 * Parse JavaScript file to extract JSDoc comments and function definitions
 */
function parseJavaScriptFile(filePath, moduleName = null, repoRoot = REPO_ROOT) {
    const content = fs.readFileSync(filePath, 'utf8');
    const functions = [];

    // Calculate relative path from repo root
    const relativePath = path.relative(repoRoot, filePath);

    // Helper to get line number from character position
    const getLineNumber = (charPos) => {
        return content.substring(0, charPos).split('\n').length;
    };

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
                source: 'javascript',
                filePath: relativePath,
                lineNumber: getLineNumber(match.index),
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
                    source: 'javascript',
                    filePath: relativePath,
                    lineNumber: i + 1, // Line numbers are 1-indexed
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
                source: 'javascript',
                filePath: relativePath,
                lineNumber: getLineNumber(match.index),
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
                const typeAnnotation = returnMatch[1] || 'any';
                const result = {
                    type: typeAnnotation,
                    description: returnMatch[2]
                };

                // Check if this is a Promise type and extract the inner type
                const promiseMatch = typeAnnotation.match(/^Promise<(.+)>$/);
                if (promiseMatch) {
                    result.promiseType = promiseMatch[1];
                }

                doc.returns = result;
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
        methods: [],     // All module-level methods (Swift + JS)
        properties: [],  // All module-level properties (Swift)
        types: []        // Type definitions (protocols with type: 'typedef')
    };

    // Find all Swift and JavaScript files in the module directory
    const files = fs.readdirSync(modulePath);
    let collectedModuleDoc = null;

    for (const file of files) {
        const filePath = path.join(modulePath, file);

        if (file.endsWith('.swift')) {
            const { protocols, moduleDocumentation } = parseSwiftFile(filePath, REPO_ROOT);

            // Collect module-level documentation (prefer from Module.swift files)
            if (moduleDocumentation && !collectedModuleDoc) {
                collectedModuleDoc = moduleDocumentation;
            } else if (moduleDocumentation && file.includes('Module.swift')) {
                // Override with Module.swift documentation if we find it
                collectedModuleDoc = moduleDocumentation;
            }

            // Process each protocol
            for (const protocol of protocols) {
                if (protocol.type === 'typedef') {
                    // Type definitions go into types array
                    moduleData.types.push(protocol);
                } else {
                    // Regular protocols - extract their methods and properties
                    if (protocol.methods) {
                        moduleData.methods.push(...protocol.methods);
                    }
                    if (protocol.properties) {
                        moduleData.properties.push(...protocol.properties);
                    }
                }
            }
        } else if (file.endsWith('.js')) {
            const functions = parseJavaScriptFile(filePath, moduleName);
            // JavaScript functions are already in the correct format
            moduleData.methods.push(...functions);
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
        types: []  // All type definitions
    };

    // Find all Swift files in the types directory
    const files = fs.readdirSync(typesPath).filter(f => f.endsWith('.swift'));

    for (const file of files) {
        const filePath = path.join(typesPath, file);
        const { protocols } = parseSwiftFile(filePath, REPO_ROOT);
        // All protocols in Engine/Types are type definitions
        typesData.types.push(...protocols.map(p => ({ ...p, category: 'type' })));
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
    let inCodeBlock = false;

    for (const line of lines) {
        const trimmed = line.trim();

        // Track code block boundaries
        if (trimmed.startsWith('```')) {
            inCodeBlock = !inCodeBlock;
            result.push(line);  // Preserve code fence
            continue;
        }

        // Preserve indentation inside code blocks
        if (inCodeBlock) {
            result.push(line);
            continue;
        }

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

    return result.join('\n');  // Changed from ' ' to '\n' to preserve line breaks
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

    // First, generate @typedef for any type definitions
    for (const typeDef of moduleData.types || []) {
        // Extract the type name from the protocol name (e.g., HSAlertAPI -> HSAlert)
        const typeName = typeDef.name.replace(/API$/, '');

        output += `/**\n`;
        output += ` * @typedef {Object} ${typeName}\n`;

        // Add property definitions
        for (const prop of typeDef.properties || []) {
            const propType = swiftTypeToJSDoc(extractPropertyType(prop.signature));
            output += ` * @property {${propType}} ${prop.name}`;
            if (prop.description) {
                output += ` - ${prop.description}`;
            }
            output += `\n`;
        }

        output += ` */\n\n`;
    }

    // Add all module methods (both Swift and JavaScript)
    for (const method of moduleData.methods || []) {
        const escapedName = escapeFunctionName(method.name);

        output += `/**\n`;
        if (method.description) {
            output += ` * ${method.description}\n`;
            output += ` *\n`;
        }
        if (method.params && method.params.length > 0) {
            for (const param of method.params) {
                const paramType = method.source === 'swift' ? swiftTypeToJSDoc(param.type) : param.type;
                const desc = param.description ? ' ' + param.description : '';
                output += ` * @param {${paramType}} ${param.name}${desc}\n`;
            }
        }
        if (method.returns) {
            const returnType = method.source === 'swift' ? swiftTypeToJSDoc(method.returns.type) : method.returns.type;
            const desc = method.returns.description ? ' ' + method.returns.description : '';
            output += ` * @returns {${returnType}}${desc}\n`;
        }
        output += ` */\n`;

        // For methods from this module, use module.name prefix
        const functionName = method.name.includes('.') ? method.name : `${moduleData.name}.${escapedName}`;
        output += `${functionName} = function(${(method.params || []).map(p => p.name).join(', ')}) {};\n\n`;
    }

    // Add module properties
    for (const prop of moduleData.properties || []) {
        output += `/**\n`;
        if (prop.description) {
            output += ` * ${prop.description}\n`;
        }
        const propType = swiftTypeToJSDoc(extractPropertyType(prop.signature));
        output += ` * @type {${propType}}\n`;
        output += ` */\n`;
        output += `${moduleData.name}.${prop.name};\n\n`;
    }

    return output;
}

/**
 * Generate JSDoc-compatible file for global types (from Engine/Types)
 */
function generateTypesJSDoc(typesData) {
    let output = '// Global Type Definitions\n\n';

    for (const protocol of typesData.types || []) {
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
            for (const method of protocol.methods || []) {
                const escapedName = escapeFunctionName(method.name);

                output += `/**\n`;
                if (method.description) {
                    output += ` * ${method.description}\n`;
                    output += ` *\n`;
                }
                for (const param of method.params || []) {
                    output += ` * @param {${swiftTypeToJSDoc(param.type)}} ${param.name}\n`;
                }
                if (method.returns) {
                    const returnDesc = method.returns.description || '';
                    output += ` * @returns {${swiftTypeToJSDoc(method.returns.type)}}${returnDesc ? ' ' + returnDesc : ''}\n`;
                }
                output += ` */\n`;
                output += `${typeName}.${escapedName} = function(${(method.params || []).map(p => p.name).join(', ')}) {};\n\n`;
            }

            // Add properties as typedef if any
            if ((protocol.properties || []).length > 0) {
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
            for (const prop of protocol.properties || []) {
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
            const initMethod = (protocol.methods || []).find(m => m.name === 'init');
            if (initMethod) {
                output += `    /**\n`;
                if (initMethod.description) {
                    output += `     * ${initMethod.description}\n`;
                    output += `     *\n`;
                }
                for (const param of initMethod.params || []) {
                    output += `     * @param {${swiftTypeToJSDoc(param.type)}} ${param.name}\n`;
                }
                output += `     */\n`;
                output += `    constructor(${(initMethod.params || []).map(p => p.name).join(', ')}) {}\n\n`;
            }

            // Add other methods
            for (const method of protocol.methods || []) {
                if (method.name === 'init') continue; // Skip init, already handled as constructor

                const escapedName = escapeFunctionName(method.name);

                output += `    /**\n`;
                if (method.description) {
                    output += `     * ${method.description}\n`;
                    output += `     *\n`;
                }
                for (const param of method.params || []) {
                    output += `     * @param {${swiftTypeToJSDoc(param.type)}} ${param.name}\n`;
                }
                if (method.returns) {
                    const returnDesc = method.returns.description || '';
                    output += `     * @returns {${swiftTypeToJSDoc(method.returns.type)}}${returnDesc ? ' ' + returnDesc : ''}\n`;
                }
                output += `     */\n`;
                output += `    ${escapedName}(${(method.params || []).map(p => p.name).join(', ')}) {}\n\n`;
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
            methodCount: (m.methods || []).length,
            typeCount: (m.types || []).length
        })),
        generatedAt: new Date().toISOString()
    };

    if (typesData) {
        indexData.types = {
            count: (typesData.types || []).length,
            protocols: (typesData.types || []).map(p => p.name)
        };
    }

    fs.writeFileSync(indexPath, JSON.stringify(indexData, null, 2));
    console.log(`\n✓ Saved module index: ${indexPath}`);

    // Save combined api.json file with all modules and types
    const apiJsonPath = path.join(__dirname, '..', 'docs', 'api.json');
    const apiJsonData = {
        modules: allModules,
        types: typesData ? (typesData.types || []) : [],
        generatedAt: new Date().toISOString()
    };
    fs.writeFileSync(apiJsonPath, JSON.stringify(apiJsonData, null, 2));
    console.log(`✓ Saved unified API JSON: ${apiJsonPath}`);

    console.log(`\n✅ Documentation extraction complete!`);
    console.log(`   - Processed ${allModules.length} modules`);
    if (typesData) {
        console.log(`   - Processed ${(typesData.types || []).length} types`);
    }
    console.log(`   - JSON files: docs/json/`);
    console.log(`   - Combined JSDoc: docs/json/combined/`);
    console.log(`   - Unified API JSON: docs/api.json`);
}

main();
