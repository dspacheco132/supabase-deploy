#!/bin/sh

# Make backup-cron.sh executable
chmod +x /app/backup-cron.sh 2>/dev/null || true

# Function to install crontab
install_crontab() {
    if [ -f /app/crontab ]; then
        crontab /app/crontab
        echo "Crontab installed successfully at $(date)"
    else
        echo "Warning: /app/crontab not found, cron jobs will not run"
    fi
}

# Install crontab initially
install_crontab

# Start cron daemon in background
crond -f -l 2 &

# Monitor crontab file for changes and reload (every 60 seconds)
(
    while true; do
        sleep 60
        if [ -f /app/crontab ]; then
            # Check if crontab file was modified
            if [ -f /tmp/crontab.mtime ]; then
                OLD_MTIME=$(cat /tmp/crontab.mtime)
                NEW_MTIME=$(stat -c %Y /app/crontab 2>/dev/null || echo "0")
                if [ "$OLD_MTIME" != "$NEW_MTIME" ]; then
                    echo "Crontab file changed, reloading..."
                    install_crontab
                    killall -HUP crond 2>/dev/null || true
                fi
            else
                install_crontab
            fi
            stat -c %Y /app/crontab > /tmp/crontab.mtime 2>/dev/null || echo "0" > /tmp/crontab.mtime
        fi
    done
) &

# Execute the main command
exec "$@"

