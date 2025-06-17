#!/bin/bash

# Keep-alive startup script for workspace session
# This script starts two background processes:
# 1. A keep-alive process that echoes every 3 minutes
# 2. A monitor process that ensures the keep-alive stays running

echo "Starting workspace keep-alive system..."

# Create log directory if it doesn't exist
mkdir -p /tmp

# Kill any existing keep-alive processes
pkill -f "Hello world, hello boss" 2>/dev/null
pkill -f "monitor_keepalive.sh" 2>/dev/null

# Start the keep-alive process with log rotation
echo "Starting keep-alive process..."
nohup bash -c 'while true; do 
    # Keep log file under 1MB (rotate when it reaches ~1000 lines)
    if [ -f /tmp/keepalive.log ] && [ $(wc -l < /tmp/keepalive.log) -gt 1000 ]; then
        tail -n 100 /tmp/keepalive.log > /tmp/keepalive.log.tmp
        mv /tmp/keepalive.log.tmp /tmp/keepalive.log
    fi
    echo "[$(date)] Hello world, hello boss! I'"'"'m waiting for the next instruction." >> /tmp/keepalive.log
    sleep 180
done' > /dev/null 2>&1 &
KEEPALIVE_PID=$!
echo "Keep-alive process started with PID: $KEEPALIVE_PID"

# Create the monitor script
cat > /tmp/monitor_keepalive.sh << 'EOF'
#!/bin/bash

# Monitor the keep-alive process
while true; do
    # Rotate monitor log if it gets too big (>1000 lines)
    if [ -f /tmp/monitor.log ] && [ $(wc -l < /tmp/monitor.log 2>/dev/null || echo 0) -gt 1000 ]; then
        tail -n 100 /tmp/monitor.log > /tmp/monitor.log.tmp
        mv /tmp/monitor.log.tmp /tmp/monitor.log
    fi
    
    # Check if the keep-alive process is running
    if pgrep -f "while true.*Hello world, hello boss" > /dev/null; then
        echo "[$(date)] Keep-alive process is running"
        
        # Check the log file
        if [ -f /tmp/keepalive.log ]; then
            echo "[$(date)] Last 3 entries from keepalive.log:"
            tail -n 3 /tmp/keepalive.log
        fi
    else
        echo "[$(date)] WARNING: Keep-alive process not found! Restarting..."
        nohup bash -c 'while true; do 
            # Keep log file under 1MB (rotate when it reaches ~1000 lines)
            if [ -f /tmp/keepalive.log ] && [ $(wc -l < /tmp/keepalive.log) -gt 1000 ]; then
                tail -n 100 /tmp/keepalive.log > /tmp/keepalive.log.tmp
                mv /tmp/keepalive.log.tmp /tmp/keepalive.log
            fi
            echo "[$(date)] Hello world, hello boss! I'"'"'m waiting for the next instruction." >> /tmp/keepalive.log
            sleep 180
        done' > /dev/null 2>&1 &
        echo "[$(date)] Keep-alive process restarted with PID: $!"
    fi
    
    # Wait 60 seconds before next check
    sleep 60
done
EOF

chmod +x /tmp/monitor_keepalive.sh

# Start the monitor process
echo "Starting monitor process..."
nohup /tmp/monitor_keepalive.sh >> /tmp/monitor.log 2>&1 &
MONITOR_PID=$!
echo "Monitor process started with PID: $MONITOR_PID"

echo "Keep-alive system is now running!"
echo "Logs:"
echo "  - Keep-alive messages: /tmp/keepalive.log"
echo "  - Monitor status: /tmp/monitor.log"
echo ""
echo "To check status: ps aux | grep -E '(keepalive|monitor_keepalive)'"
echo "To stop: pkill -f 'Hello world, hello boss' && pkill -f 'monitor_keepalive.sh'"