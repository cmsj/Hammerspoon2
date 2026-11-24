/**
 * Tests for scripts/docs-params.js.
 *
 * Run with: npm run test:scripts
 */

const test = require('node:test');
const assert = require('node:assert/strict');

const {
    extractParamDescriptions,
    extractReturnDetails,
    parseObjectType,
    locateObjectType,
    displayType,
    fieldsOf,
    typeWithFieldDocs
} = require('../docs-params');

test('parseObjectType takes an object literal apart', () => {
    assert.deepEqual(parseObjectType('{source: string, ref?: string, fn?: (a: number, b: {x: string}) => void}'), [
        { name: 'source', optional: false, tsType: 'string' },
        { name: 'ref', optional: true, tsType: 'string' },
        { name: 'fn', optional: true, tsType: '(a: number, b: {x: string}) => void' }
    ]);
    assert.deepEqual(parseObjectType('{a: Record<string, any> | "x,y"; b: number[]}'), [
        { name: 'a', optional: false, tsType: 'Record<string, any> | "x,y"' },
        { name: 'b', optional: false, tsType: 'number[]' }
    ]);
});

test('parseObjectType rejects types that are not a single object literal', () => {
    assert.equal(parseObjectType('string'), null);
    assert.equal(parseObjectType('{[key: string]: any}'), null);
    assert.equal(parseObjectType('{a: string} | {b: number}'), null);
    assert.equal(parseObjectType('{}'), null);
    assert.equal(parseObjectType(null), null);
});

test('Swift-style nested bullets become fields, with continuation lines', () => {
    const params = extractParamDescriptions([
        'Does a thing.',
        '- Parameter name: The name',
        '- Parameter options?: How to do it',
        '  - force?: {boolean} Do it even if',
        '    it is done already',
        '  - retry: How to retry',
        '    - count: {number} How many times',
        '- Returns: Nothing'
    ]);
    assert.equal(params.name.fields, undefined);
    assert.equal(params.options.optional, true);
    assert.equal(params.options.tsType, '{force?: boolean, retry: {count: number}}');
    const [force, retry] = params.options.fields;
    assert.equal(force.name, 'force');
    assert.equal(force.description, 'Do it even if it is done already');
    assert.equal(retry.fields[0].name, 'count');
    assert.equal(retry.fields[0].tsType, 'number');
});

test('JS-style Parameters lists keep fields out of the parameters', () => {
    const params = extractParamDescriptions([
        'Parameters:',
        ' - spec: The hotkey',
        '   - mods: {string[]} Modifiers',
        '   - message?: {string} A message',
        ' - other: {number} Another parameter',
        'Returns: A hotkey'
    ]);
    assert.deepEqual(Object.keys(params), ['spec', 'other']);
    assert.deepEqual(params.spec.fields.map(f => f.name), ['mods', 'message']);
    assert.equal(params.spec.tsType, '{mods: string[], message?: string}');
    assert.equal(params.other.fields, undefined);
});

test('an explicit object type fills in the types of untyped fields', () => {
    const params = extractParamDescriptions([
        '- Parameter options: {{a: string, b?: number}} Options',
        '  - a: The a',
        '  - b?: The b'
    ]);
    assert.equal(params.options.tsType, '{a: string, b?: number}');
    assert.deepEqual(params.options.fields.map(f => f.tsType), ['string', 'number']);
});

test('fieldsOf derives fields from an object type when none are documented', () => {
    const fields = fieldsOf({ tsType: '{path?: string, inner: {x: number}}' });
    assert.deepEqual(fields.map(f => [f.name, f.optional, f.tsType]), [
        ['path', true, 'string'],
        ['inner', false, '{x: number}']
    ]);
    assert.equal(fields[1].fields[0].name, 'x');
    assert.deepEqual(fieldsOf({ tsType: 'string' }), []);
});

test('locateObjectType finds the object inside promises, arrays and nullable unions', () => {
    for (const type of ['{a: string}', 'Promise<{a: string}>', '{a: string}[]', 'Array<{a: string}>',
        '{a: string} | null', 'Promise<({a: string} | undefined)[]>']) {
        const found = locateObjectType(type);
        assert.equal(type.slice(found.start, found.end), '{a: string}', type);
    }
    assert.equal(locateObjectType('{a: string} | {b: number}'), null);
    assert.equal(locateObjectType('{a: string} | string'), null);
    assert.equal(locateObjectType('Promise<boolean>'), null);
    assert.equal(displayType('Promise<{a: string}[] | null>'), 'Promise<object[] | null>');
    assert.equal(displayType('string'), 'string');
});

test('documented fields merge with a declared type, keeping fields only the type has', () => {
    const params = extractParamDescriptions([
        '- Parameter options: {{a: string, b?: number}} Options',
        '  - b?: The b'
    ]);
    assert.deepEqual(params.options.fields.map(f => [f.name, f.tsType, f.description]), [
        ['a', 'string', ''],
        ['b', 'number', 'The b']
    ]);
});

test('extractReturnDetails reads fields and continuation lines under Returns:', () => {
    const details = extractReturnDetails([
        '- Parameter x: An x',
        '- Returns: {Promise<{id: number, tags: string[]}[]>} The things,',
        '  oldest first',
        '  - id: Its identifier',
        '- Example:'
    ], 'Promise<{id: number, tags: string[]}[]>', 'The things,');
    assert.equal(details.description, 'The things, oldest first');
    assert.deepEqual(details.fields.map(f => [f.name, f.tsType, f.description]), [
        ['id', 'number', 'Its identifier'],
        ['tags', 'string[]', '']
    ]);
    assert.equal(extractReturnDetails(['No returns here'], 'string', ''), null);
});

test('typeWithFieldDocs documents each field in place, at any depth', () => {
    const fields = [
        { name: 'a', optional: true, tsType: 'string', description: 'The */ a' },
        { name: 'b', optional: false, tsType: '{c: number}', description: '', fields: [
            { name: 'c', optional: false, tsType: 'number', description: 'The c' }
        ] }
    ];
    assert.equal(typeWithFieldDocs('Promise<{a?: string, b: {c: number}}[]>', fields, '    '), [
        'Promise<{',
        '        /** The *\\/ a */',
        '        a?: string;',
        '        b: {',
        '            /** The c */',
        '            c: number;',
        '        };',
        '    }[]>'
    ].join('\n'));
    assert.equal(typeWithFieldDocs('{a: string}', [{ name: 'a', tsType: 'string', description: '' }], ''), '{a: string}');
});
