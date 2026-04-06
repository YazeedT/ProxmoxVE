#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: YazeedT (Adapted from MickLesk)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/grimmory-tools/grimmory

APP="Grimmory"
var_tags="${var_tags:-books;grimmory}"
var_cpu="${var_cpu:-3}"
var_ram="${var_ram:-3072}"
var_disk="${var_disk:-7}"
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

  if [[ ! -d /opt/grimmory ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "grimmory" "grimmory-tools/grimmory"; then
    JAVA_VERSION="25" setup_java
    NODE_VERSION="22" setup_nodejs
    setup_mariadb
    setup_yq

    msg_info "Stopping Service"
    systemctl stop grimmory
    msg_ok "Stopped Service"

    if grep -qE "^GRIMMORY_(DATA_PATH|BOOKDROP_PATH|BOOKS_PATH|PORT)=" /opt/grimmory_storage/.env 2>/dev/null; then
      msg_info "Migrating old environment variables"
      sed -i 's/^GRIMMORY_DATA_PATH=/APP_PATH_CONFIG=/g' /opt/grimmory_storage/.env
      sed -i 's/^GRIMMORY_BOOKDROP_PATH=/APP_BOOKDROP_FOLDER=/g' /opt/grimmory_storage/.env
      sed -i '/^GRIMMORY_BOOKS_PATH=/d' /opt/grimmory_storage/.env
      sed -i '/^GRIMMORY_PORT=/d' /opt/grimmory_storage/.env
      msg_ok "Migrated old environment variables"
    fi

    msg_info "Backing up old installation"
    mv /opt/grimmory /opt/grimmory_bak
    msg_ok "Backed up old installation"

    fetch_and_deploy_gh_release "grimmory" "grimmory-tools/grimmory" "tarball"

    # Build frontend
    if [[ -d /opt/grimmory/frontend ]]; then
      msg_info "Building Frontend"
      cd /opt/grimmory/frontend
      $STD npm install --force
      $STD npm run build --configuration=production || $STD npm run build
      msg_ok "Built Frontend"
    elif [[ -d /opt/grimmory/booklore-ui ]]; then
      # fallback for repositories using legacy name
      msg_info "Building Frontend (legacy booklore-ui)"
      cd /opt/grimmory/booklore-ui
      $STD npm install --force
      $STD npm run build --configuration=production || $STD npm run build
      msg_ok "Built Frontend"
    else
      msg_info "No frontend directory found; skipping frontend build"
      msg_ok "Frontend build skipped"
    fi

    # Build backend
    if [[ -d /opt/grimmory/booklore-api ]]; then
      msg_info "Building Backend"
      cd /opt/grimmory/booklore-api
      APP_VERSION=$(get_latest_github_release "grimmory-tools/grimmory")
      yq eval ".app.version = \"${APP_VERSION}\"" -i src/main/resources/application.yaml 2>/dev/null || true
      $STD ./gradlew clean build --no-daemon
      mkdir -p /opt/grimmory/dist
      JAR_PATH=$(find /opt/grimmory/booklore-api/build/libs -maxdepth 1 -type f -name "booklore-api-*.jar" ! -name "*plain*" | head -n1)
      if [[ -z "$JAR_PATH" ]]; then
        msg_error "Backend JAR not found"
        exit
      fi
      cp "$JAR_PATH" /opt/grimmory/dist/app.jar
      msg_ok "Built Backend"
    else
      msg_info "No backend directory found; skipping backend build"
      msg_ok "Backend build skipped"
    fi

    msg_info "Starting Service"
    systemctl start grimmory
    systemctl reload nginx || true
    rm -rf /opt/grimmory_bak
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:6060${CL}"
