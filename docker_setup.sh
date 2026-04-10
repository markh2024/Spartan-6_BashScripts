#!/bin/bash

set -e

# ===== Colours =====
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ===== Paths =====
TAR_SRC="/home/mark/Installs/Spartan6/Xilinx_ISE_DS_Lin_14.7_1015_1.tar"
TAR_DEST="/home/mark/xilinx-docker"
INSTALLER_DIR="$TAR_DEST/Xilinx_ISE_14.7"
ROOT_DEST="/root/.Xilinx"
REGISTRY="$TAR_DEST/container_registry.json"

# ===== Ensure registry file exists =====
init_registry() {
    mkdir -p "$TAR_DEST"
    if [ ! -f "$REGISTRY" ]; then
        echo "[]" > "$REGISTRY"
        echo -e "${GREEN}[✓] Registry created at $REGISTRY${RESET}"
    fi
}

# ===== Register a container in the JSON db =====
register_container() {
    local app_name="$1"
    local container_name="$2"
    local container_id
    container_id=$(docker inspect --format='{{.Id}}' "$container_name" 2>/dev/null || echo "unknown")
    local created
    created=$(date '+%Y-%m-%d %H:%M:%S')

    python3 - "$app_name" "$container_name" "$container_id" "$created" "$REGISTRY" <<'PYEOF'
import json, sys

app_name, container_name, container_id, created, registry_file = sys.argv[1:6]

with open(registry_file, 'r') as f:
    data = json.load(f)

# Remove any existing entry with the same container name
data = [e for e in data if e.get('container_name') != container_name]

entry = {
    "app_name": app_name,
    "container_name": container_name,
    "container_id": container_id,
    "created": created
}
data.append(entry)

# Re-number from 1
for i, e in enumerate(data):
    e['index'] = i + 1

with open(registry_file, 'w') as f:
    json.dump(data, f, indent=2)

print(f"[✓] Registered '{container_name}' as index {entry['index']}")
PYEOF
}

# ===== List all registered containers =====
list_containers() {
    init_registry
    echo ""
    echo -e "${CYAN}${BOLD}======================================================${RESET}"
    echo -e "${CYAN}${BOLD}         Registered Container Registry${RESET}"
    echo -e "${CYAN}${BOLD}======================================================${RESET}"

    python3 - "$REGISTRY" <<'PYEOF'
import json, subprocess, sys

registry_file = sys.argv[1]

with open(registry_file, 'r') as f:
    data = json.load(f)

if not data:
    print("  No containers registered.\n")
else:
    print(f"  {'#':<4} {'App':<22} {'Container Name':<28} {'Status':<12} {'Created'}")
    print(f"  {'-'*4} {'-'*22} {'-'*28} {'-'*12} {'-'*19}")
    for e in data:
        name = e.get('container_name', 'unknown')
        try:
            result = subprocess.run(
                ['docker', 'inspect', '--format={{.State.Status}}', name],
                capture_output=True, text=True
            )
            status = result.stdout.strip() if result.returncode == 0 else 'not found'
        except Exception:
            status = 'error'
        print(f"  {e['index']:<4} {e.get('app_name','?'):<22} {name:<28} {status:<12} {e.get('created','?')}")
PYEOF

    echo ""
    echo -e "${YELLOW}--- Docker Disk Usage ---${RESET}"
    docker system df
    echo ""
}

# ===== Delete a container by index number =====
delete_by_index() {
    list_containers
    echo -e "${YELLOW}Enter the number of the container to delete (or 0 to cancel):${RESET}"
    read -rp "  > " idx

    if [ "$idx" = "0" ]; then
        echo "Cancelled."
        return
    fi

    python3 - "$idx" "$REGISTRY" <<'PYEOF'
import json, subprocess, sys

idx, registry_file = int(sys.argv[1]), sys.argv[2]

with open(registry_file, 'r') as f:
    data = json.load(f)

target = next((e for e in data if e['index'] == idx), None)

if not target:
    print(f"  No entry with index {idx} found.")
    sys.exit(1)

name = target.get('container_name', '')
print(f"[*] Stopping and removing container: {name}")
result = subprocess.run(['docker', 'rm', '-f', name], capture_output=True, text=True)
if result.returncode == 0:
    print(f"[✓] Docker container '{name}' removed.")
else:
    print(f"[!] Docker said: {result.stderr.strip()} (may already be gone)")

data = [e for e in data if e['index'] != idx]
for i, e in enumerate(data):
    e['index'] = i + 1

with open(registry_file, 'w') as f:
    json.dump(data, f, indent=2)

print(f"[✓] Entry removed from registry.")
PYEOF
}

# ===== Delete ALL containers in registry =====
delete_all_containers() {
    echo -e "${RED}This will stop and remove ALL registered containers. Are you sure? (y/n):${RESET}"
    read -rp "  > " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        return
    fi

    python3 - "$REGISTRY" <<'PYEOF'
import json, subprocess, sys

registry_file = sys.argv[1]

with open(registry_file, 'r') as f:
    data = json.load(f)

if not data:
    print("  Nothing registered to remove.")
else:
    for e in data:
        name = e.get('container_name', '')
        print(f"[*] Removing: {name}")
        subprocess.run(['docker', 'rm', '-f', name], capture_output=True)
    print(f"\n[✓] Removed {len(data)} container(s) from Docker and registry.")

with open(registry_file, 'w') as f:
    json.dump([], f, indent=2)
PYEOF
}

# ===== Full Docker prune (catches unregistered orphans too) =====
prune_all() {
    echo ""
    echo -e "${YELLOW}--- Current disk usage before prune ---${RESET}"
    docker system df
    echo ""
    echo -e "${RED}This will prune ALL stopped containers, unused images and networks.${RESET}"
    echo -e "${RED}This includes containers NOT in the registry. Continue? (y/n):${RESET}"
    read -rp "  > " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        return
    fi
    docker system prune -af
    echo ""
    echo -e "${GREEN}--- Disk usage after prune ---${RESET}"
    docker system df

    # Clear registry since everything is gone
    echo "[]" > "$REGISTRY"
    echo -e "${GREEN}[✓] Registry cleared.${RESET}"
}

# ===== Container Manager Menu =====
container_manager_menu() {
    init_registry
    while true; do
        clear
        echo -e "${CYAN}${BOLD}=============================================${RESET}"
        echo -e "${CYAN}${BOLD}       Docker Container Manager${RESET}"
        echo -e "${CYAN}${BOLD}=============================================${RESET}"
        echo -e "  ${BOLD}1)${RESET} List registered containers + disk usage"
        echo -e "  ${BOLD}2)${RESET} Delete a container by number"
        echo -e "  ${BOLD}3)${RESET} Delete ALL registered containers"
        echo -e "  ${BOLD}4)${RESET} Full Docker prune (removes all orphans too)"
        echo -e "  ${BOLD}5)${RESET} Continue to ISE Docker setup"
        echo -e "  ${BOLD}0)${RESET} Exit"
        echo -e "${CYAN}${BOLD}=============================================${RESET}"
        read -rp "  Select option: " choice

        case $choice in
            1) list_containers;         read -rp "  Press Enter to continue..." ;;
            2) delete_by_index;         read -rp "  Press Enter to continue..." ;;
            3) delete_all_containers;   read -rp "  Press Enter to continue..." ;;
            4) prune_all;               read -rp "  Press Enter to continue..." ;;
            5) break ;;
            0) exit 0 ;;
            *) echo -e "${RED}  Invalid option${RESET}"; sleep 1 ;;
        esac
    done
}

# ===== Keep sudo alive =====
keep_sudo_alive() {
    while true; do
        sudo -n true
        sleep 60
    done 2>/dev/null &
}

# ===== Install Docker =====
do_update() {
    echo -e "${GREEN}Installing Docker...${RESET}"
    sudo apt update
    sudo apt install -y docker.io python3
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo usermod -aG docker "$USER"
}

# ===== Extract Installer =====
extract_installer() {
    echo -e "${GREEN}Checking installer archive...${RESET}"

    if [ ! -f "$TAR_SRC" ]; then
        echo -e "${RED}ERROR: Installer not found:${RESET} $TAR_SRC"
        exit 1
    fi

    mkdir -p "$TAR_DEST"

    echo -e "${GREEN}Extracting installer...${RESET}"
    tar -xf "$TAR_SRC" -C "$TAR_DEST"

    EXTRACTED=$(find "$TAR_DEST" -maxdepth 1 -type d -iname "*ISE*" | head -n 1)

    if [ -z "$EXTRACTED" ]; then
        echo -e "${RED}ERROR: Extraction failed — no ISE directory found in archive${RESET}"
        exit 1
    fi

    if [ "$EXTRACTED" != "$INSTALLER_DIR" ]; then
        mv "$EXTRACTED" "$INSTALLER_DIR"
    fi

    echo -e "${GREEN}Installer ready at:${RESET} $INSTALLER_DIR"
}

# ===== Create Dockerfile and config =====
make_directories() {
    echo -e "${GREEN}Preparing Docker environment...${RESET}"

    mkdir -p "$TAR_DEST"
    cd "$TAR_DEST"

    cat > Dockerfile <<'EOF'
FROM ubuntu:14.04

ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture i386 && apt-get update && apt-get install -y \
    libc6:i386 libstdc++6:i386 libncurses5:i386 \
    libx11-6:i386 libxext6:i386 libxtst6:i386 libxi6:i386 \
    libxrender1:i386 libglib2.0-0:i386 libsm6:i386 libice6:i386 \
    libxt6:i386 libxrandr2:i386 libgtk2.0-0:i386 libidn11:i386 \
    libglu1-mesa:i386 libpangox-1.0-0:i386 libpangoxft-1.0-0:i386 \
    libx11-6 libxext6 libxtst6 libxi6 libxrender1 \
    libglib2.0-0 libsm6 libice6 libxt6 libxrandr2 \
    build-essential wget sudo python \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN useradd -ms /bin/bash xilinx && \
    echo "xilinx ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN mkdir -p /root/.Xilinx/xinstall && \
    touch /root/.Xilinx/xinstall/xinstall.log && \
    mkdir -p /opt/Xilinx && \
    chown xilinx:xilinx /opt/Xilinx

COPY Xilinx_ISE_14.7 /home/xilinx/ise_installer
COPY ise_config.txt /home/xilinx/ise_installer/ise_config.txt

RUN chmod +x /home/xilinx/ise_installer/xsetup && \
    chown -R xilinx:xilinx /home/xilinx/ise_installer

USER xilinx
WORKDIR /home/xilinx

RUN echo "source /opt/Xilinx/14.7/ISE_DS/settings64.sh" >> ~/.bashrc

ENV XILINX=/opt/Xilinx/14.7/ISE_DS/ISE
ENV PATH=$PATH:$XILINX/bin/lin64:$XILINX/bin/lin
EOF

    cat > ise_config.txt <<'EOF'
Edition=ISE Design Suite: WebPACK
Product=ISE
Destination=/opt/Xilinx
CreateDesktopShortcuts=0
CreateProgramGroupShortcuts=0
CreateFileAssociation=0
EnableWebTalk=0
InstallCableDrivers=1
EOF

    echo -e "${GREEN}Dockerfile and ise_config.txt created${RESET}"
}

# ===== Build Docker Image =====
build_docker() {
    echo -e "${GREEN}Building Docker image...${RESET}"
    cd "$TAR_DEST"

    docker build -t xilinx-ise . 2>&1 | tee build.log

    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        echo -e "${RED}Build failed. See $TAR_DEST/build.log for details.${RESET}"
        exit 1
    fi

    echo -e "${GREEN}Docker build complete!${RESET}"
}

# ===== Shutdown Prompt =====
shutdown_prompt() {
    echo ""
    read -rp "Shutdown system now? (y/n): " confirm

    if [[ $confirm =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Shutting down...${RESET}"
        sudo reboot -h now
    else
        echo -e "${GREEN}Done. No shutdown.${RESET}"
    fi
}

# ===== MAIN =====
main() {
    # Container manager runs first — clean up before anything is created
    container_manager_menu

    echo -e "${GREEN}Requesting sudo access...${RESET}"
    sudo -v

    keep_sudo_alive

    sudo rm -rf "$ROOT_DEST"
    sudo rm -rf "$TAR_DEST"

    do_update
    extract_installer
    make_directories
    build_docker

    # Re-init registry (TAR_DEST was wiped above)
    init_registry
    register_container "Xilinx ISE 14.7" "xilinx_ise_container"

    shutdown_prompt
}

main
