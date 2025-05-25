#!/usr/bin/env node

/**
 * AppleScript Consistency Verification Script
 * 
 * This script ensures that AppleScript code in test files matches
 * the corresponding AppleScript code in the source files.
 */

import { readFileSync, existsSync, readdirSync, statSync } from 'fs';
import { join, basename, relative } from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import crypto from 'crypto';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const projectRoot = join(__dirname, '..');

// ANSI color codes
const colors = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m'
};

function log(message, color = '') {
  console.log(`${color}${message}${colors.reset}`);
}

function logStep(step) {
  console.log(`\n${colors.bright}${colors.blue}━━━ ${step} ━━━${colors.reset}\n`);
}

function logSuccess(message) {
  log(`✅ ${message}`, colors.green);
}

function logError(message) {
  log(`❌ ${message}`, colors.red);
}

function logWarning(message) {
  log(`⚠️  ${message}`, colors.yellow);
}

/**
 * Extract AppleScript content from a Swift file
 */
function extractAppleScriptsFromSwift(filePath) {
  const content = readFileSync(filePath, 'utf8');
  const scripts = new Map();
  
  // Match static functions that return AppleScript
  // Pattern: static func xxxScript(...) -> String { ... return """ ... """ }
  const functionPattern = /static\s+func\s+(\w+Script)\s*\([^)]*\)\s*->\s*String\s*\{([\s\S]*?)\n\s*\}/g;
  let match;
  
  while ((match = functionPattern.exec(content)) !== null) {
    const functionName = match[1];
    const functionBody = match[2];
    
    // Extract the triple-quoted string from the function body
    const tripleQuotePattern = /"""([\s\S]*?)"""/g;
    let scriptMatch;
    
    while ((scriptMatch = tripleQuotePattern.exec(functionBody)) !== null) {
      const scriptContent = scriptMatch[1].trim();
      
      // Check if it looks like AppleScript (contains common keywords)
      if (scriptContent.match(/\b(tell|end tell|to|on|return|set|get|if|then|else|repeat|with|application)\b/)) {
        // Remove Swift string interpolation for comparison
        const cleanedScript = scriptContent.replace(/\\\([^)]+\)/g, '<PARAM>');
        scripts.set(functionName, normalizeAppleScript(cleanedScript));
      }
    }
  }
  
  // Also match direct variable assignments with triple quotes
  const variablePattern = /(?:let|var)\s+(\w+)\s*=\s*"""([\s\S]*?)"""/g;
  
  while ((match = variablePattern.exec(content)) !== null) {
    const variableName = match[1];
    const scriptContent = match[2].trim();
    
    // Check if it looks like AppleScript
    if (scriptContent.match(/\b(tell|end tell|to|on|return|set|get|if|then|else|repeat|with|application)\b/)) {
      scripts.set(variableName, normalizeAppleScript(scriptContent));
    }
  }
  
  return scripts;
}

/**
 * Normalize AppleScript for comparison
 */
function normalizeAppleScript(script) {
  return script
    .split('\n')
    .map(line => line.trim())
    .filter(line => line.length > 0 && !line.startsWith('--')) // Remove comments
    .join('\n')
    .replace(/\s+/g, ' ') // Normalize whitespace
    .trim();
}

/**
 * Read AppleScript from .applescript file
 */
function readAppleScriptFile(filePath) {
  const content = readFileSync(filePath, 'utf8');
  return normalizeAppleScript(content);
}

/**
 * Calculate hash for script content
 */
function hashScript(script) {
  return crypto.createHash('md5').update(script).digest('hex').substring(0, 8);
}

/**
 * Find all Swift files containing AppleScript
 */
function findSwiftFilesWithAppleScript(dir) {
  const files = [];
  
  function walk(currentDir) {
    const entries = readdirSync(currentDir);
    
    for (const entry of entries) {
      const fullPath = join(currentDir, entry);
      const stat = statSync(fullPath);
      
      if (stat.isDirectory() && !entry.startsWith('.') && entry !== 'Tests') {
        walk(fullPath);
      } else if (entry.endsWith('.swift')) {
        files.push(fullPath);
      }
    }
  }
  
  walk(dir);
  return files;
}

/**
 * Find all AppleScript test files
 */
function findAppleScriptTestFiles(dir) {
  const files = [];
  
  function walk(currentDir) {
    const entries = readdirSync(currentDir);
    
    for (const entry of entries) {
      const fullPath = join(currentDir, entry);
      const stat = statSync(fullPath);
      
      if (stat.isDirectory() && !entry.startsWith('.')) {
        walk(fullPath);
      } else if (entry.endsWith('.applescript')) {
        files.push(fullPath);
      }
    }
  }
  
  if (existsSync(dir)) {
    walk(dir);
  }
  
  return files;
}

/**
 * Main verification function
 */
function verifyAppleScriptConsistency() {
  logStep('AppleScript Consistency Verification');
  
  const cliPath = join(projectRoot, 'cli');
  const sourcePath = join(cliPath, 'Sources', 'TerminatorCLI');
  const testPath = join(cliPath, 'Tests', 'AppleScriptTests');
  
  // Find all Swift files with AppleScript
  log('Searching for AppleScript in Swift source files...', colors.cyan);
  const swiftFiles = findSwiftFilesWithAppleScript(sourcePath);
  
  if (swiftFiles.length === 0) {
    logWarning('No Swift files with AppleScript found');
    return true;
  }
  
  log(`Found ${swiftFiles.length} Swift files containing AppleScript`, colors.cyan);
  
  // Extract all AppleScripts from source files
  const sourceScripts = new Map();
  
  for (const file of swiftFiles) {
    const relPath = relative(sourcePath, file);
    const scripts = extractAppleScriptsFromSwift(file);
    
    if (scripts.size > 0) {
      log(`  ${relPath}: ${scripts.size} scripts`, colors.cyan);
      
      for (const [name, content] of scripts) {
        sourceScripts.set(`${relPath}:${name}`, {
          file: relPath,
          name,
          content,
          hash: hashScript(content)
        });
      }
    }
  }
  
  log(`\nTotal AppleScripts in source: ${sourceScripts.size}`, colors.cyan);
  
  // Find all AppleScript test files
  log('\nSearching for AppleScript test files...', colors.cyan);
  const testFiles = findAppleScriptTestFiles(testPath);
  
  if (testFiles.length === 0) {
    logWarning('No AppleScript test files found');
    return true;
  }
  
  log(`Found ${testFiles.length} AppleScript test files`, colors.cyan);
  
  // Map test scripts
  const testScripts = new Map();
  
  for (const file of testFiles) {
    const relPath = relative(testPath, file);
    const content = readAppleScriptFile(file);
    const scriptName = basename(file, '.applescript');
    
    testScripts.set(scriptName, {
      file: relPath,
      content,
      hash: hashScript(content)
    });
  }
  
  // Compare scripts
  logStep('Comparing AppleScripts');
  
  let hasInconsistencies = false;
  const unmatched = new Set(testScripts.keys());
  
  // Check if test scripts match source scripts
  for (const [sourceKey, sourceScript] of sourceScripts) {
    let foundMatch = false;
    
    for (const [testName, testScript] of testScripts) {
      if (sourceScript.hash === testScript.hash) {
        logSuccess(`Match found: ${sourceScript.name} (${sourceScript.file}) ↔ ${testScript.file}`);
        unmatched.delete(testName);
        foundMatch = true;
        break;
      }
    }
    
    if (!foundMatch) {
      // Try partial name matching
      for (const [testName, testScript] of testScripts) {
        if (testName.toLowerCase().includes(sourceScript.name.toLowerCase()) ||
            sourceScript.name.toLowerCase().includes(testName.toLowerCase())) {
          
          if (sourceScript.hash !== testScript.hash) {
            logError(`Content mismatch: ${sourceScript.name} (${sourceScript.file}) ≠ ${testScript.file}`);
            log(`  Source hash: ${sourceScript.hash}`, colors.yellow);
            log(`  Test hash:   ${testScript.hash}`, colors.yellow);
            hasInconsistencies = true;
          } else {
            logSuccess(`Match found: ${sourceScript.name} (${sourceScript.file}) ↔ ${testScript.file}`);
            unmatched.delete(testName);
            foundMatch = true;
          }
          break;
        }
      }
      
      if (!foundMatch) {
        logWarning(`No test found for: ${sourceScript.name} (${sourceScript.file})`);
      }
    }
  }
  
  // Report unmatched test files
  if (unmatched.size > 0) {
    log('\nTest files without matching source:', colors.yellow);
    for (const testName of unmatched) {
      logWarning(`  ${testScripts.get(testName).file}`);
    }
  }
  
  // Summary
  logStep('Summary');
  
  if (hasInconsistencies) {
    logError('AppleScript inconsistencies detected!');
    log('\nTo fix inconsistencies:', colors.cyan);
    log('1. Update test files to match source AppleScripts');
    log('2. Or update source AppleScripts to match test files');
    log('3. Ensure all source AppleScripts have corresponding tests');
    return false;
  } else {
    logSuccess('All AppleScripts are consistent between source and tests');
    return true;
  }
}

// Export for use in other scripts
export { verifyAppleScriptConsistency };

// Run if called directly
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const success = verifyAppleScriptConsistency();
  process.exit(success ? 0 : 1);
}