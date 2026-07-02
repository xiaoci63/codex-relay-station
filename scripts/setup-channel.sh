#!/bin/bash
# Setup ChatGPT channel in New API
# Run this after deploying and getting your ChatGPT access token
#
# Usage:
#   chmod +x setup-channel.sh && sudo ./setup-channel.sh

set -e

DB_PATH="/opt/relay-station/data/new-api/one-api.db"

echo "============================================"
echo "  ChatGPT Channel Setup"
echo "============================================"
echo ""

# Check if database exists
if [ ! -f "$DB_PATH" ]; then
    echo "Error: Database not found at $DB_PATH"
    echo "Make sure New API is running first."
    exit 1
fi

# Get access token
read -p "Enter your ChatGPT access token (from https://chatgpt.com/api/auth/session): " ACCESS_TOKEN

if [ -z "$ACCESS_TOKEN" ]; then
    echo "Error: Access token cannot be empty"
    exit 1
fi

CREATED_TIME=$(date +%s)

# Add channel to database
echo "Adding ChatGPT channel..."
sqlite3 "$DB_PATH" "INSERT INTO channels (type, key, name, status, base_url, models, model_mapping, \`group\`, used_quota, created_time, priority, weight, test_model, auto_ban, status_code_mapping, other, tag, setting) VALUES (1, '${ACCESS_TOKEN}', 'ChatGPT-Plus-Chat2API', 1, 'http://172.17.0.1:5005', 'gpt-4o,gpt-4o-mini,o1,o1-mini,o3,o3-mini,o4-mini,gpt-5.5', '{}', 'default', 0, ${CREATED_TIME}, 10, 0, 'gpt-4o-mini', 1, '', '', '', '');"

# Add to abilities table
echo "Registering models..."
CHANNEL_ID=$(sqlite3 "$DB_PATH" "SELECT id FROM channels WHERE name='ChatGPT-Plus-Chat2API' ORDER BY id DESC LIMIT 1;")

for MODEL in gpt-4o gpt-4o-mini o1 o1-mini o3 o3-mini o4-mini gpt-5.5; do
    sqlite3 "$DB_PATH" "INSERT INTO abilities (\`group\`, model, channel_id, enabled, priority, weight, tag) VALUES ('default', '${MODEL}', ${CHANNEL_ID}, 1, 10, 0, '');" 2>/dev/null || true
done

# Enable self-use mode (skip pricing checks)
sqlite3 "$DB_PATH" "INSERT OR REPLACE INTO options (key, value) VALUES ('SelfUseModeEnabled', 'true');"

# Create admin user if not exists
echo "Setting up admin account..."
ADMIN_EXISTS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE username='root';")
if [ "$ADMIN_EXISTS" -eq 0 ]; then
    echo "Admin user 'root' will be created on first web login."
fi

# Set admin role to 100 (root admin)
sqlite3 "$DB_PATH" "UPDATE users SET role = 100 WHERE username = 'root';" 2>/dev/null || true

# Restart New API to reload
echo "Restarting services..."
cd /opt/relay-station
docker compose restart new-api
sleep 5

# Verify
echo ""
echo "Channels configured:"
sqlite3 "$DB_PATH" "SELECT id, name, base_url, models FROM channels;"
echo ""
echo "Models registered:"
sqlite3 "$DB_PATH" "SELECT model, channel_id, enabled FROM abilities;"
echo ""
echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo ""
echo "  Next steps:"
echo "  1. Login to admin panel and change password"
echo "  2. Create user accounts"
echo "  3. Generate API keys for each user"
echo "  4. Test: curl http://localhost:3000/v1/chat/completions \\"
echo "         -H 'Authorization: Bearer sk-YOUR_KEY' \\"
echo "         -H 'Content-Type: application/json' \\"
echo "         -d '{\"model\":\"gpt-4o-mini\",\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}'"
echo ""
