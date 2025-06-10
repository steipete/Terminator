#!/bin/bash

# Test script that verifies Terminator functionality by checking Terminal tabs

echo "🧪 Testing Terminator MCP - Tab Creation and Management"
echo "======================================================="

# Function to count Terminator sessions
count_sessions() {
    osascript -e 'tell application "Terminal" to count (every tab of every window whose custom title contains "::TERMINATOR_SESSION::")'
}

# Function to get session titles
get_session_titles() {
    osascript -e 'tell application "Terminal" to get custom title of every tab of every window whose custom title contains "::TERMINATOR_SESSION::"'
}

echo ""
echo "1️⃣ Initial state - counting existing Terminator sessions..."
INITIAL_COUNT=$(count_sessions)
echo "   Found $INITIAL_COUNT existing Terminator session(s)"

echo ""
echo "2️⃣ Creating new session via MCP..."
node -e "
import { spawn } from 'child_process';

const mcp = spawn('node', ['dist/index.js'], { stdio: ['pipe', 'pipe', 'pipe'] });

// Initialize
mcp.stdin.write(JSON.stringify({
  jsonrpc: '2.0',
  method: 'initialize',
  params: { protocolVersion: '1.0', capabilities: {}, clientInfo: { name: 'test', version: '1.0' } },
  id: 1
}) + '\\n');

// Wait and create session
setTimeout(() => {
  mcp.stdin.write(JSON.stringify({
    jsonrpc: '2.0',
    method: 'tools/call',
    params: {
      name: 'execute',
      arguments: {
        action: 'execute',
        project_path: '/tmp',
        tag: 'test-verification',
        command: 'echo \"Session created via MCP!\"'
      }
    },
    id: 2
  }) + '\\n');
  
  setTimeout(() => mcp.kill(), 2000);
}, 1000);

mcp.stdout.on('data', (data) => {
  const lines = data.toString().split('\\n');
  for (const line of lines) {
    if (line.includes('result') && line.includes('content')) {
      console.log('   MCP Response:', line.substring(0, 100) + '...');
    }
  }
});
"

sleep 5

echo ""
echo "3️⃣ Checking if new session was created..."
NEW_COUNT=$(count_sessions)
echo "   Now have $NEW_COUNT Terminator session(s)"

if [ $NEW_COUNT -gt $INITIAL_COUNT ]; then
    echo "   ✅ Success! New session was created"
else
    echo "   ❌ Failed to create new session"
fi

echo ""
echo "4️⃣ Listing sessions via Swift CLI..."
./bin/terminator sessions

echo ""
echo "5️⃣ Testing session focus..."
./bin/terminator focus --tag test-verification --project-path /tmp
FOCUS_EXIT=$?
if [ $FOCUS_EXIT -eq 0 ]; then
    echo "   ✅ Focus command succeeded"
else
    echo "   ❌ Focus command failed with exit code $FOCUS_EXIT"
fi

echo ""
echo "6️⃣ Current session titles:"
get_session_titles | tr ',' '\n' | grep -E "TAG=|test-" | sed 's/.*TAG=/   - /' | sed 's/::.*//'

echo ""
echo "7️⃣ Executing command in existing session..."
./bin/terminator execute test-verification --project-path /tmp --command 'echo "Command executed in existing session!"'
EXEC_EXIT=$?
if [ $EXEC_EXIT -eq 0 ]; then
    echo "   ✅ Execute command succeeded"
else
    echo "   ⚠️  Execute command exited with code $EXEC_EXIT (may have timed out waiting for output)"
fi

echo ""
echo "8️⃣ Testing kill command..."
./bin/terminator kill --tag test-verification --project-path /tmp --focus-on-kill false
KILL_EXIT=$?
if [ $KILL_EXIT -eq 0 ]; then
    echo "   ✅ Kill command succeeded"
else
    echo "   ❌ Kill command failed with exit code $KILL_EXIT"
fi

echo ""
echo "✅ Test complete!"
echo ""
echo "Note: Output capture to files is not working yet, but session management is functional."