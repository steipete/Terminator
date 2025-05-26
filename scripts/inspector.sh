#!/bin/bash

# Script to build and run MCP inspector for Terminator
# Usage: npm run inspector

set -e  # Exit on error

echo "🔨 Building project..."
npm run build

echo ""
echo "🔍 Starting MCP Inspector..."
echo "📡 The inspector will open in your browser"
echo "🛑 Press Ctrl+C to stop"
echo ""

npx @modelcontextprotocol/inspector node dist/index.js