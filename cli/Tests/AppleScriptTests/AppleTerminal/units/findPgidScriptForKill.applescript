-- Run ps command to find processes on this TTY
set psCommand to "ps -t ttys001 -o pgid,pid,ppid,command | grep -v 'PID' | head -1 | awk '{print $1}'"
set psResult to do shell script psCommand
return psResult