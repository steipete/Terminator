#!/bin/bash
# simulate_build.sh - Simulates a long-running build process for testing
# Usage: ./simulate_build.sh [duration_in_seconds] [lines_per_second]

duration=${1:-10}
lines_per_second=${2:-1}
interval=$(echo "scale=2; 1 / $lines_per_second" | bc -l)

echo "Starting simulated build process..."
echo "Duration: ${duration}s, Lines per second: ${lines_per_second}"
echo "=========================================="

total_lines=$((duration * lines_per_second))
current_line=0

while [ $current_line -lt $total_lines ]; do
    current_line=$((current_line + 1))
    timestamp=$(date '+%H:%M:%S')
    
    case $((current_line % 10)) in
        1) echo "[$timestamp] [1/8] Analyzing dependencies...";;
        2) echo "[$timestamp] [2/8] Compiling SourceFile${current_line}.swift";;
        3) echo "[$timestamp] [3/8] Linking object files...";;
        4) echo "[$timestamp] [4/8] Running code generation...";;
        5) echo "[$timestamp] [5/8] Processing resources...";;
        6) echo "[$timestamp] [6/8] Creating bundle structure...";;
        7) echo "[$timestamp] [7/8] Optimizing binary...";;
        8) echo "[$timestamp] [8/8] Finalizing build artifacts...";;
        9) echo "[$timestamp] Build progress: $((current_line * 100 / total_lines))%";;
        0) echo "[$timestamp] Memory usage: $((RANDOM % 1000 + 200))MB, CPU: $((RANDOM % 100))%";;
    esac
    
    sleep $interval
done

echo "=========================================="
echo "✅ Build completed successfully in ${duration}s"
echo "📦 Generated artifacts: MyApp.app ($(((RANDOM % 50) + 10))MB)"
echo "🎯 Exit code: 0"