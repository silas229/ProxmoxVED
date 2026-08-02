#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Yooooomi/your_spotify

APP="Your-Spotify"
var_tags="${var_tags:-media;music}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/your_spotify ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "your_spotify" "Yooooomi/your_spotify"; then
    msg_info "Stopping Services"
    systemctl stop your-spotify-backend your-spotify-client
    msg_ok "Stopped Services"

    create_backup /opt/your_spotify/apps/server/.env

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "your_spotify" "Yooooomi/your_spotify" "tarball"

    NODE_VERSION="22" NODE_MODULE="pnpm@latest" setup_nodejs

    restore_backup

    msg_info "Installing pnpm Dependencies"
    cd /opt/your_spotify
    $STD pnpm install --frozen-lockfile --dangerously-allow-all-builds
    msg_ok "Installed pnpm Dependencies"

    msg_info "Building Backend"
    $STD pnpm --filter server build
    msg_ok "Built Backend"

    msg_info "Running Database Migration"
    cd /opt/your_spotify/apps/server
    set -a && source /opt/your_spotify/apps/server/.env && set +a
    $STD node build/index.js --migrate
    msg_ok "Ran Database Migration"

    API_ENDPOINT=$(grep '^API_ENDPOINT=' /opt/your_spotify/apps/server/.env | cut -d= -f2-)

    msg_info "Building Client"
    cd /opt/your_spotify
    $STD pnpm --filter client build
    cp /opt/your_spotify/apps/client/build/variables-template.js /opt/your_spotify/apps/client/build/variables.js
    sed -i "s;__API_ENDPOINT__;${API_ENDPOINT};g" /opt/your_spotify/apps/client/build/variables.js
    sed -i "s#connect-src \(.*\);#connect-src 'self' ${API_ENDPOINT}/;#g" /opt/your_spotify/apps/client/build/index.html
    sed -i "s#frame-ancestors \(.*\);#frame-ancestors 'none';#g" /opt/your_spotify/apps/client/scripts/run/serve.json
    msg_ok "Built Client"

    msg_info "Starting Services"
    systemctl start your-spotify-backend your-spotify-client
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access the client using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
echo -e "${INFO}${YW}The backend API is reachable at:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
