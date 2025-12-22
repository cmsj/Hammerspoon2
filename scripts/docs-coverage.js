#!/usr/bin/env node

/**
 * Documentation Coverage Report
 * 
 * Analyzes the extracted documentation to show coverage statistics
 * and identify areas that need better documentation.
 */

const fs = require('fs');
const path = require('path');

const JSON_DIR = path.join(__dirname, '..', 'docs', 'json');
const INDEX_FILE = path.join(JSON_DIR, 'index.json');

function analyzeModule(moduleFile) {
    const data = JSON.parse(fs.readFileSync(moduleFile, 'utf8'));
    
    const stats = {
        name: data.name,
        swift: {
            totalMethods: 0,
            documentedMethods: 0,
            totalProperties: 0,
            documentedProperties: 0
        },
        javascript: {
            totalFunctions: 0,
            documentedFunctions: 0
        }
    };
    
    // Analyze Swift protocols
    for (const protocol of data.swift.protocols) {
        stats.swift.totalMethods += protocol.methods.length;
        stats.swift.totalProperties += protocol.properties.length;
        
        for (const method of protocol.methods) {
            if (method.description && method.description.trim().length > 0) {
                stats.swift.documentedMethods++;
            }
        }

        for (const prop of protocol.properties) {
            if (prop.description && prop.description.trim().length > 0) {
                stats.swift.documentedProperties++;
            }
        }
    }
    
    // Analyze JavaScript functions
    stats.javascript.totalFunctions = data.javascript.functions.length;
    for (const func of data.javascript.functions) {
        if (func.documentation && func.documentation.description && 
            func.documentation.description.trim().length > 0) {
            stats.javascript.documentedFunctions++;
        }
    }
    
    return stats;
}

function calculateCoverage(documented, total) {
    if (total === 0) return 100;
    return Math.round((documented / total) * 100);
}

function main() {
    console.log('Documentation Coverage Report');
    console.log('============================\n');
    
    if (!fs.existsSync(INDEX_FILE)) {
        console.error('Error: Documentation not generated. Run: npm run docs:extract');
        process.exit(1);
    }
    
    const index = JSON.parse(fs.readFileSync(INDEX_FILE, 'utf8'));
    const allStats = [];
    
    for (const module of index.modules) {
        const moduleFile = path.join(JSON_DIR, `${module.name}.json`);
        const stats = analyzeModule(moduleFile);
        allStats.push(stats);
    }
    
    // Calculate totals
    const totals = {
        swift: { methods: 0, documentedMethods: 0, properties: 0, documentedProperties: 0 },
        javascript: { functions: 0, documentedFunctions: 0 }
    };
    
    for (const stats of allStats) {
        totals.swift.methods += stats.swift.totalMethods;
        totals.swift.documentedMethods += stats.swift.documentedMethods;
        totals.swift.properties += stats.swift.totalProperties;
        totals.swift.documentedProperties += stats.swift.documentedProperties;
        totals.javascript.functions += stats.javascript.totalFunctions;
        totals.javascript.documentedFunctions += stats.javascript.documentedFunctions;
    }
    
    // Print module details
    console.log('Module Breakdown:');
    console.log('-'.repeat(80));
    console.log('Module              Swift Methods  Swift Props  JS Functions');
    console.log('-'.repeat(80));
    
    for (const stats of allStats) {
        const methodCov = calculateCoverage(stats.swift.documentedMethods, stats.swift.totalMethods);
        const propCov = calculateCoverage(stats.swift.documentedProperties, stats.swift.totalProperties);
        const jsCov = calculateCoverage(stats.javascript.documentedFunctions, stats.javascript.totalFunctions);
        
        const methodStr = `${stats.swift.documentedMethods}/${stats.swift.totalMethods} (${methodCov}%)`;
        const propStr = `${stats.swift.documentedProperties}/${stats.swift.totalProperties} (${propCov}%)`;
        const jsStr = `${stats.javascript.documentedFunctions}/${stats.javascript.totalFunctions} (${jsCov}%)`;
        
        console.log(
            `${stats.name.padEnd(20)} ${methodStr.padEnd(15)} ${propStr.padEnd(13)} ${jsStr}`
        );
    }
    
    // Print summary
    console.log('-'.repeat(80));
    console.log('\nOverall Summary:');
    console.log('-'.repeat(80));
    
    const methodCov = calculateCoverage(totals.swift.documentedMethods, totals.swift.methods);
    const propCov = calculateCoverage(totals.swift.documentedProperties, totals.swift.properties);
    const jsCov = calculateCoverage(totals.javascript.documentedFunctions, totals.javascript.functions);
    
    console.log(`Swift Methods:     ${totals.swift.documentedMethods}/${totals.swift.methods} (${methodCov}%)`);
    console.log(`Swift Properties:  ${totals.swift.documentedProperties}/${totals.swift.properties} (${propCov}%)`);
    console.log(`JS Functions:      ${totals.javascript.documentedFunctions}/${totals.javascript.functions} (${jsCov}%)`);
    
    const totalItems = totals.swift.methods + totals.swift.properties + totals.javascript.functions;
    const totalDocumented = totals.swift.documentedMethods + totals.swift.documentedProperties + 
                           totals.javascript.documentedFunctions;
    const overallCov = calculateCoverage(totalDocumented, totalItems);
    
    console.log(`\nTotal:             ${totalDocumented}/${totalItems} (${overallCov}%)`);
    console.log('-'.repeat(80));
    
    // Recommendations
    if (overallCov < 80) {
        console.log('\n⚠️  Documentation coverage is below 80%');
        console.log('Consider adding documentation to:');
        
        for (const stats of allStats) {
            const modCov = calculateCoverage(
                stats.swift.documentedMethods + stats.swift.documentedProperties + 
                stats.javascript.documentedFunctions,
                stats.swift.totalMethods + stats.swift.totalProperties + 
                stats.javascript.totalFunctions
            );
            
            if (modCov < 70) {
                console.log(`  - ${stats.name} (${modCov}% coverage)`);
            }
        }
    } else {
        console.log('\n✅ Good documentation coverage!');
    }
}

main();
