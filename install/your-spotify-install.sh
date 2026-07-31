#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Yooooomi/your_spotify

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_mongodb

NODE_VERSION="22" NODE_MODULE="pnpm@latest" setup_nodejs

fetch_and_deploy_gh_release "your_spotify" "Yooooomi/your_spotify" "tarball"

msg_info "Installing pnpm Dependencies"
cd /opt/your_spotify
$STD pnpm install --frozen-lockfile
msg_ok "Installed pnpm Dependencies"

API_ENDPOINT="http://${LOCAL_IP}:8080"
CLIENT_ENDPOINT="http://${LOCAL_IP}:3000"

echo -e "\nTo finish setup, you need a Spotify application:"
echo -e "1. Go to https://developer.spotify.com/dashboard and create an app"
echo -e "2. Set its Redirect URI to: ${API_ENDPOINT}/oauth/spotify/callback"
echo -e "3. Copy the Client ID and Client Secret below\n"
read -r -p "Spotify Client ID: " SPOTIFY_PUBLIC
read -r -p "Spotify Client Secret: " SPOTIFY_SECRET

msg_info "Configuring Your Spotify"
cat <<EOF >/opt/your_spotify/apps/server/.env
MONGO_ENDPOINT=mongodb://127.0.0.1:27017/your_spotify
API_ENDPOINT=${API_ENDPOINT}
CLIENT_ENDPOINT=${CLIENT_ENDPOINT}
PORT=8080
SPOTIFY_PUBLIC=${SPOTIFY_PUBLIC}
SPOTIFY_SECRET=${SPOTIFY_SECRET}
EOF
msg_ok "Configured Your Spotify"

msg_info "Building Backend"
cd /opt/your_spotify
$STD pnpm --filter server build
msg_ok "Built Backend"

msg_info "Running Database Migration"
cd /opt/your_spotify/apps/server
set -a && source /opt/your_spotify/apps/server/.env && set +a
$STD node build/index.js --migrate
msg_ok "Ran Database Migration"

msg_info "Building Client"
cd /opt/your_spotify
$STD pnpm --filter client build
cp /opt/your_spotify/apps/client/build/variables-template.js /opt/your_spotify/apps/client/build/variables.js
sed -i "s;__API_ENDPOINT__;${API_ENDPOINT};g" /opt/your_spotify/apps/client/build/variables.js
sed -i "s#connect-src \(.*\);#connect-src 'self' ${API_ENDPOINT}/;#g" /opt/your_spotify/apps/client/build/index.html
sed -i "s#frame-ancestors \(.*\);#frame-ancestors 'none';#g" /opt/your_spotify/apps/client/scripts/run/serve.json
msg_ok "Built Client"

msg_info "Installing serve"
$STD npm install -g serve
msg_ok "Installed serve"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/your-spotify-backend.service
[Unit]
Description=Your Spotify Backend
After=network.target mongod.service
Requires=mongod.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/your_spotify/apps/server
EnvironmentFile=/opt/your_spotify/apps/server/.env
ExecStart=/usr/bin/node /opt/your_spotify/apps/server/build/index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/your-spotify-client.service
[Unit]
Description=Your Spotify Client
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/your_spotify/apps/client
ExecStart=/usr/bin/serve -c /opt/your_spotify/apps/client/scripts/run/serve.json -s -l tcp://0.0.0.0:3000 /opt/your_spotify/apps/client/build/
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now your-spotify-backend
systemctl enable -q --now your-spotify-client
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
