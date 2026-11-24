//
//  docs-params.js
//  Hammerspoon 2
//
//  Parameter and return value documentation shared by the docs generators: parsing `- Parameter`
//  and `- Returns` doc comments (including the fields of an object, documented as nested
//  bullets), and finding, taking apart and rewriting the object types those fields belong to.
//

// Bullets that start a new DocC section, rather than naming a parameter or field
const SECTION_NAMES = new Set(['Returns', 'Return', 'Throws', 'Note', 'Example', 'Parameters', 'Parameter']);

/**
 * Parse a parameter description that may start with a TypeScript type hint.
 * A hint looks like "{(path: string) => void} Called when done" — the braced
 * expression becomes the explicit TS type and the rest is the human description.
 * Returns { description, tsType: string|null }.
 */
function parseParamDescription(raw) {
    const trimmed = raw.trim();
    if (trimmed.startsWith('{')) {
        // Find the closing brace at depth 0
        let depth = 0;
        let end = -1;
        for (let i = 0; i < trimmed.length; i++) {
            if (trimmed[i] === '{') depth++;
            else if (trimmed[i] === '}') {
                depth--;
                if (depth === 0) { end = i; break; }
            }
        }
        if (end !== -1) {
            const tsType = trimmed.slice(1, end).trim();
            const description = trimmed.slice(end + 1).trim();
            return { description, tsType };
        }
    }
    return { description: trimmed, tsType: null };
}

/**
 * Split a TypeScript type at the given separator characters, ignoring any inside brackets,
 * generics or string literals. The `>` of an arrow (`=>`) doesn't close a generic.
 * Returns [{ text, start }], where start is each part's offset in text.
 */
function splitTopLevel(text, separators) {
    const parts = [];
    let depth = 0;
    let quote = null;
    let start = 0;
    for (let i = 0; i < text.length; i++) {
        const c = text[i];
        if (quote) {
            if (c === quote && text[i - 1] !== '\\') quote = null;
        } else if (c === '"' || c === "'" || c === '`') {
            quote = c;
        } else if ('({[<'.includes(c)) {
            depth++;
        } else if (')}]'.includes(c) || (c === '>' && text[i - 1] !== '=')) {
            depth--;
        } else if (depth === 0 && separators.includes(c)) {
            parts.push({ text: text.slice(start, i), start });
            start = i + 1;
        }
    }
    parts.push({ text: text.slice(start), start });
    return parts;
}

// The index of the bracket that closes the one at text[0], or -1
function closingIndex(text) {
    let depth = 0;
    let quote = null;
    for (let i = 0; i < text.length; i++) {
        const c = text[i];
        if (quote) {
            if (c === quote && text[i - 1] !== '\\') quote = null;
        } else if (c === '"' || c === "'" || c === '`') {
            quote = c;
        } else if ('({[<'.includes(c)) {
            depth++;
        } else if (')}]'.includes(c) || (c === '>' && text[i - 1] !== '=')) {
            depth--;
            if (depth === 0) return i;
        }
    }
    return -1;
}

/**
 * Take an object type literal (`{a: string, b?: number}`) apart into its fields.
 * Returns [{ name, optional, tsType }], or null if tsType isn't a single object literal
 * with named fields (a union, an index signature such as `{[key: string]: any}`, etc).
 */
function parseObjectType(tsType) {
    if (!tsType) return null;
    const text = tsType.trim();
    if (!text.startsWith('{') || closingIndex(text) !== text.length - 1) return null;

    const body = text.slice(1, -1).trim();
    if (!body) return null;

    const fields = [];
    for (const member of splitTopLevel(body, ',;')) {
        const trimmed = member.text.trim();
        if (!trimmed) continue;
        const match = trimmed.match(/^(\w+)(\?)?\s*:\s*([\s\S]+)$/);
        if (!match) return null;
        fields.push({ name: match[1], optional: !!match[2], tsType: match[3].trim() });
    }
    return fields.length > 0 ? fields : null;
}

/**
 * Find the object type literal that a type is about: the type itself, or the object inside a
 * `Promise<…>`, `Array<…>`, `…[]`, parentheses, or a union with only `null`/`undefined` beside it.
 * So `Promise<{a: string}[] | null>` is about `{a: string}`.
 * Returns { start, end, fields } (end exclusive, offsets into tsType), or null.
 */
function locateObjectType(tsType) {
    if (!tsType) return null;

    const locate = (text, offset) => {
        const lead = text.length - text.trimStart().length;
        const t = text.trim();
        offset += lead;
        if (!t) return null;

        const fields = parseObjectType(t);
        if (fields) return { start: offset, end: offset + t.length, fields };

        const generic = t.match(/^(Promise|Array)</);
        if (generic && t.endsWith('>') && closingIndex(t.slice(generic[1].length)) === t.length - generic[1].length - 1) {
            const innerStart = generic[0].length;
            return locate(t.slice(innerStart, -1), offset + innerStart);
        }
        if (t.endsWith('[]')) {
            return locate(t.slice(0, -2), offset);
        }
        if (t.startsWith('(') && closingIndex(t) === t.length - 1) {
            return locate(t.slice(1, -1), offset + 1);
        }
        const members = splitTopLevel(t, '|');
        if (members.length > 1) {
            const others = members.filter(m => !['null', 'undefined'].includes(m.text.trim()));
            if (others.length === 1) return locate(others[0].text, offset + others[0].start);
        }
        return null;
    };

    return locate(tsType, 0);
}

/**
 * The object type literal for a list of fields, e.g. `{a: string, b?: number}`.
 * A field without a type is `any`.
 */
function objectTypeFromFields(fields) {
    const members = fields.map(f => `${f.name}${f.optional ? '?' : ''}: ${f.tsType || 'any'}`);
    return `{${members.join(', ')}}`;
}

/**
 * The fields to show for a parameter, field or return value: its documented ones, or else
 * those of its object type. Each field's own fields are filled in the same way.
 * Returns an array (empty if it has no fields).
 */
function fieldsOf(node) {
    const fields = (node.fields && node.fields.length > 0)
        ? node.fields
        : (locateObjectType(node.tsType)?.fields || []).map(f => ({ ...f, description: '' }));
    return fields.map(f => ({ ...f, fields: fieldsOf(f) }));
}

/**
 * A type to show beside a list of its fields: the object type it's about becomes `object`, so
 * `Promise<{a: string}[]>` shows as `Promise<object[]>` above its fields.
 */
function displayType(tsType) {
    const found = locateObjectType(tsType);
    if (!found) return tsType;
    return tsType.slice(0, found.start) + 'object' + tsType.slice(found.end);
}

/**
 * Merge documented fields with the object type a node declares, so neither loses anything:
 * declared fields keep their order and types and gain their documentation, a documented field
 * without a `{type}` hint takes the declared one, and documented fields the type doesn't declare
 * come last (with a warning, as the type and the docs disagree). A node without a declared object
 * type gets the one its fields add up to.
 */
function resolveFieldTypes(node, where) {
    if (!node.fields || node.fields.length === 0) {
        delete node.fields;
        return;
    }

    // Merge before resolving the fields themselves, so a field's declared type (and through it,
    // its own fields' types) comes from here when it isn't documented on the field
    const declared = locateObjectType(node.tsType)?.fields;
    if (declared) {
        const documented = new Map(node.fields.map(f => [f.name, f]));
        const merged = declared.map(d => {
            const doc = documented.get(d.name);
            documented.delete(d.name);
            return doc ? { ...doc, optional: d.optional, tsType: d.tsType } : { ...d, description: '' };
        });
        for (const extra of documented.values()) {
            console.warn(`⚠ ${where}: field '${extra.name}' is documented but not in its type ${node.tsType}`);
            merged.push(extra);
        }
        node.fields = merged;
    }

    for (const field of node.fields) {
        resolveFieldTypes(field, `${where}.${field.name}`);
    }

    if (!node.tsType) {
        node.tsType = objectTypeFromFields(node.fields);
    }
}

const lineIndent = line => line.length - line.trimStart().length;

/**
 * Read the bullets nested under a parameter or return value (whose own line is indented by
 * rootIndent) into root.fields, from lines[from] on. Bullets can nest further, and a deeper
 * indented line that isn't a bullet continues the description above it. Returns the index of
 * the first line that isn't part of them.
 */
function readNestedFields(lines, from, rootIndent, root) {
    const stack = [{ indent: rootIndent, node: root }];
    let i = from;
    for (; i < lines.length; i++) {
        const trimmed = lines[i].trim();
        const indent = lineIndent(lines[i]);
        if (!trimmed || indent <= rootIndent) break;

        const bullet = trimmed.match(/^-\s+(\w+)(\?)?\s*:\s*(.*)$/);
        if (bullet && !SECTION_NAMES.has(bullet[1])) {
            while (stack[stack.length - 1].indent >= indent) stack.pop();
            const { description, tsType } = parseParamDescription(bullet[3]);
            const node = { name: bullet[1], description, optional: !!bullet[2], tsType, fields: [] };
            stack[stack.length - 1].node.fields.push(node);
            stack.push({ indent, node });
        } else if (!trimmed.startsWith('-') && indent > stack[stack.length - 1].indent) {
            const node = stack[stack.length - 1].node;
            node.description = node.description ? `${node.description} ${trimmed}` : trimmed;
        } else {
            break;
        }
    }
    return i;
}

/**
 * Extract parameter descriptions from documentation.
 * Returns a map of { paramName: { name, description, optional, tsType, fields? } }.
 * A parameter name suffixed with '?' in the doc comment (e.g. "- Parameter allWindows?: ...")
 * sets optional: true, which causes the TypeScript generator to emit `name?: type`.
 * A description starting with "{TypeScript type}" (e.g. "{(x: number) => void}")
 * sets tsType, which overrides the Swift-derived TypeScript type in the output.
 *
 * Bullets indented under a parameter document the fields of an object it takes, and can nest:
 *
 *     - Parameter options?: How to do it
 *       - force?: {boolean} Do it even if it's done already
 *       - retry?: How to retry
 *         - count: {number} How many times
 *
 * Lines indented deeper than a parameter's or field's bullet, that aren't bullets themselves,
 * continue its description. docLines must keep their indentation.
 */
function extractParamDescriptions(docLines) {
    const descriptions = {};
    let inParams = false;
    let listIndent = null;

    const readParam = (i, name, optional, text) => {
        const { description, tsType } = parseParamDescription(text);
        const node = { name, description, optional: !!optional, tsType, fields: [] };
        descriptions[name] = node;
        return readNestedFields(docLines, i + 1, lineIndent(docLines[i]), node);
    };

    let i = 0;
    while (i < docLines.length) {
        const line = docLines[i];
        const trimmed = line.trim();
        const indent = lineIndent(line);

        // Check for Parameters section (with or without leading dash)
        if (trimmed === '- Parameters:' || trimmed === '- Parameters' ||
            trimmed === 'Parameters:' || trimmed === 'Parameters') {
            inParams = true;
            listIndent = null;
            i++;
            continue;
        }

        // Check for single Parameter (with or without leading dash).
        // The parameter name may be suffixed with '?' to mark it as optional in TypeScript.
        const singleParamMatch = trimmed.match(/^-?\s*Parameter\s+(\w+)(\?)?\s*:\s*(.+)$/);
        if (singleParamMatch) {
            inParams = false;
            i = readParam(i, singleParamMatch[1], singleParamMatch[2], singleParamMatch[3]);
            continue;
        }

        // If we're in Parameters section, look for individual parameters
        const bullet = trimmed.match(/^-\s+(\w+)(\?)?\s*:\s*(.*)$/);
        if (inParams && bullet && !SECTION_NAMES.has(bullet[1]) && (listIndent === null || indent === listIndent)) {
            listIndent = indent;
            i = readParam(i, bullet[1], bullet[2], bullet[3]);
            continue;
        }

        // Stop if we hit a non-parameter line or Returns section
        if (inParams && trimmed && (trimmed.startsWith('- ') || indent < listIndent ||
            trimmed.startsWith('Returns:'))) {
            inParams = false;
        }
        i++;
    }

    for (const node of Object.values(descriptions)) {
        resolveFieldTypes(node, node.name);
    }
    return descriptions;
}

/**
 * Read the fields of the object a method returns, documented as bullets nested under its
 * `Returns:` line just as a parameter's are, along with any continuation of its description.
 * tsType is the return type the fields belong to, e.g. `Promise<{a: string}[]>`.
 * Returns { description, fields? }, or null if docLines has no `Returns:` line.
 */
function extractReturnDetails(docLines, tsType, description) {
    const index = docLines.findIndex(line => /^-?\s*Returns?\s*:/.test(line.trim()));
    if (index === -1) return null;

    const root = { name: 'returns', description, tsType, fields: [] };
    readNestedFields(docLines, index + 1, lineIndent(docLines[index]), root);
    resolveFieldTypes(root, 'returns');
    return root.fields ? { description: root.description, fields: root.fields } : { description: root.description };
}

/**
 * Rewrite a type so the object it's about lists its fields one per line, each under its
 * description as a doc comment, so editors show them. Types whose fields have no descriptions
 * are left as they are. indent is the indentation of the line the type starts on.
 */
function typeWithFieldDocs(tsType, fields, indent, escape = text => text.replace(/\*\//g, '*\\/')) {
    const hasDocs = list => (list || []).some(f => f.description || hasDocs(f.fields));
    if (!tsType || !hasDocs(fields)) return tsType;

    const found = locateObjectType(tsType);
    if (!found) return tsType;

    const inner = `${indent}    `;
    const members = fields.map(f => {
        const doc = f.description ? `${inner}/** ${escape(f.description)} */\n` : '';
        const type = typeWithFieldDocs(f.tsType || 'any', f.fields, inner, escape);
        return `${doc}${inner}${f.name}${f.optional ? '?' : ''}: ${type};\n`;
    });
    const literal = `{\n${members.join('')}${indent}}`;
    return tsType.slice(0, found.start) + literal + tsType.slice(found.end);
}

module.exports = {
    parseParamDescription,
    extractParamDescriptions,
    extractReturnDetails,
    parseObjectType,
    locateObjectType,
    objectTypeFromFields,
    displayType,
    fieldsOf,
    typeWithFieldDocs
};
