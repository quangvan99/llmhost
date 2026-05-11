#!/bin/bash
REMOTE="root@206.189.238.85"
PID_FILE="/tmp/ssh_tunnel.pid"

start() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat $PID_FILE)" 2>/dev/null; then
        echo "Tunnels already running (PID: $(cat $PID_FILE))"
        return
    fi
    ssh -fN \
        -o "ServerAliveInterval=30" \
        -o "ServerAliveCountMax=3" \
        -R 0.0.0.0:13002:localhost:13001 \
        -R 0.0.0.0:14002:localhost:14001 \
        -R 0.0.0.0:8889:localhost:8889 \
        -R 0.0.0.0:8890:localhost:8890 \
        -R 0.0.0.0:8891:localhost:8891 \
        "$REMOTE"
    # lấy PID của tiến trình ssh vừa tạo
    sleep 1
    PID=$(pgrep -f "ssh -fN.*$REMOTE" | tail -1)
    echo "$PID" > "$PID_FILE"
    echo "Tunnels started (PID: $PID)"
}

stop() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill "$PID" 2>/dev/null; then
            echo "Tunnels stopped (PID: $PID)"
        else
            echo "Process $PID not found, cleaning up PID file"
        fi
        rm -f "$PID_FILE"
    else
        echo "No PID file found. Trying to kill by pattern..."
        pkill -f "ssh -fN.*$REMOTE" && echo "Killed" || echo "No tunnel found"
    fi
}

status() {
    echo "=== Active SSH tunnels to $REMOTE ==="
    PROCS=$(pgrep -a ssh 2>/dev/null | grep "$REMOTE")
    if [ -n "$PROCS" ]; then
        echo "$PROCS"
    else
        echo "No active tunnels"
    fi
}

case "$1" in
    start)   start ;;
    stop)    stop ;;
    restart) stop; sleep 1; start ;;
    status)  status ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
