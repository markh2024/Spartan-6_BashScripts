#!/bin/bash

INSTALL_DIR="/home/mark/xilinx-docker"
SCRIPT_PATH="$INSTALL_DIR/run_ise.sh"

echo "[*] Creating ISE launcher script..."

cat > "$SCRIPT_PATH" << 'EOF'
#!/bin/bash

IMAGE_NAME="xilinx-ise"
CONTAINER_NAME="xilinx_ise_container"
INSTALL_DIR="/home/mark/xilinx-docker"
REGISTRY="$INSTALL_DIR/container_registry.json"

# ===== Colours =====
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ===== Registry helpers =====
init_registry() {
    mkdir -p "$INSTALL_DIR"
    if [ ! -f "$REGISTRY" ]; then
        echo "[]" > "$REGISTRY"
    fi
}

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
data = [e for e in data if e.get('container_name') != container_name]
entry = {"app_name": app_name, "container_name": container_name,
         "container_id": container_id, "created": created}
data.append(entry)
for i, e in enumerate(data):
    e['index'] = i + 1
with open(registry_file, 'w') as f:
    json.dump(data, f, indent=2)
print(f"[✓] Registered '{container_name}' as index {entry['index']}")
PYEOF
}

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
                capture_output=True, text=True)
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

delete_by_index() {
    list_containers
    echo -e "${YELLOW}Enter the number to delete (or 0 to cancel):${RESET}"
    read -rp "  > " idx
    [ "$idx" = "0" ] && { echo "Cancelled."; return; }

    python3 - "$idx" "$REGISTRY" <<'PYEOF'
import json, subprocess, sys
idx, registry_file = int(sys.argv[1]), sys.argv[2]
with open(registry_file, 'r') as f:
    data = json.load(f)
target = next((e for e in data if e['index'] == idx), None)
if not target:
    print(f"  No entry with index {idx}.")
    sys.exit(1)
name = target.get('container_name', '')
print(f"[*] Removing container: {name}")
result = subprocess.run(['docker', 'rm', '-f', name], capture_output=True, text=True)
print(f"[✓] Removed." if result.returncode == 0 else f"[!] {result.stderr.strip()}")
data = [e for e in data if e['index'] != idx]
for i, e in enumerate(data):
    e['index'] = i + 1
with open(registry_file, 'w') as f:
    json.dump(data, f, indent=2)
print("[✓] Registry updated.")
PYEOF
}

prune_all() {
    echo ""
    echo -e "${YELLOW}--- Disk usage before prune ---${RESET}"
    docker system df
    echo -e "${RED}Remove ALL stopped containers, unused images, networks? (y/n):${RESET}"
    read -rp "  > " confirm
    [[ ! $confirm =~ ^[Yy]$ ]] && { echo "Cancelled."; return; }
    docker system prune -af
    echo "[]" > "$REGISTRY"
    echo -e "${GREEN}[✓] Pruned and registry cleared.${RESET}"
    echo ""
    docker system df
}

# ===== Registry Manager Menu =====
registry_menu() {
    init_registry
    while true; do
        clear
        echo -e "${CYAN}${BOLD}=============================================${RESET}"
        echo -e "${CYAN}${BOLD}       Docker Container Manager${RESET}"
        echo -e "${CYAN}${BOLD}=============================================${RESET}"
        echo -e "  ${BOLD}1)${RESET} List containers + disk usage"
        echo -e "  ${BOLD}2)${RESET} Delete a container by number"
        echo -e "  ${BOLD}3)${RESET} Full Docker prune (all orphans)"
        echo -e "  ${BOLD}0)${RESET} Back to main menu"
        echo -e "${CYAN}${BOLD}=============================================${RESET}"
        read -rp "  Select option: " choice
        case $choice in
            1) list_containers;   read -rp "  Press Enter..." ;;
            2) delete_by_index;   read -rp "  Press Enter..." ;;
            3) prune_all;         read -rp "  Press Enter..." ;;
            0) break ;;
            *) echo -e "${RED}  Invalid option${RESET}"; sleep 1 ;;
        esac
    done
}

# ===== X11 =====
function allow_x11() {
    xhost +local:docker >/dev/null 2>&1
}

# ===== Instructions =====
function instructions() {
    clear
    echo "========================================="
    echo "     Xilinx ISE Docker - Instructions"
    echo "========================================="
    echo ""
    echo "FIRST TIME SETUP:"
    echo "  1) Run option 2 (Install ISE)"
    echo "  2) Follow the GUI installer"
    echo ""
    echo "NORMAL USE:"
    echo "  - Option 3 → Launch ISE (design tools)"
    echo "  - Option 4 → iMPACT (program FPGA)"
    echo ""
    echo "NOTES:"
    echo "  - Licence file (.lic) must be in ~/Downloads"
    echo "  - Board must be plugged in via USB"
    echo "  - Uses --privileged for JTAG access"
    echo "  - If GUI fails → check DISPLAY and xhost"
    echo ""
    read -p "Press Enter to continue..."
}

# ===== Start or reuse persistent container =====
function start_container() {
    allow_x11

    docker start $CONTAINER_NAME 2>/dev/null || \
    docker run -dit \
        --name $CONTAINER_NAME \
        --privileged \
        -e DISPLAY=$DISPLAY \
        -e XILINXD_LICENSE_FILE=/downloads \
        -v /tmp/.X11-unix:/tmp/.X11-unix \
        -v /dev/bus/usb:/dev/bus/usb \
        -v ~/Downloads:/downloads \
        $IMAGE_NAME \
        tail -f /dev/null

    # Register in case it's new
    init_registry
    register_container "Xilinx ISE 14.7" "$CONTAINER_NAME"
}

# ===== Open shell =====
function run_container() {
    start_container
    docker exec -it $CONTAINER_NAME /bin/bash
}

# ===== Install ISE into persistent container then commit =====
function install_ise() {
    allow_x11
    echo "[*] Removing any previous install container..."
    docker rm -f $CONTAINER_NAME 2>/dev/null || true

    echo "[*] Starting persistent install container..."
    docker run -dit \
        --name $CONTAINER_NAME \
        --privileged \
        -e DISPLAY=$DISPLAY \
        -v /tmp/.X11-unix:/tmp/.X11-unix \
        -v /dev/bus/usb:/dev/bus/usb \
        -v ~/Downloads:/downloads \
        $IMAGE_NAME \
        tail -f /dev/null

    echo "[*] Running xsetup inside container as root..."
    docker exec -it \
        -e DISPLAY=$DISPLAY \
        -u root \
        $CONTAINER_NAME \
        bash -c "cd /home/xilinx/ise_installer && ./xsetup"

    echo "[*] Committing installed state back to image..."
    docker commit $CONTAINER_NAME $IMAGE_NAME
    echo -e "${GREEN}[✓] Image updated with ISE installed.${RESET}"

    init_registry
    register_container "Xilinx ISE 14.7" "$CONTAINER_NAME"

    read -p "Press Enter..."
}

# ===== Launch ISE GUI =====
function launch_ise() {
    start_container
    docker exec -it \
        -e DISPLAY=$DISPLAY \
        -e XILINXD_LICENSE_FILE=/downloads \
        $CONTAINER_NAME bash -c \
        "source /opt/Xilinx/14.7/ISE_DS/settings64.sh && ise"
}

# ===== Launch iMPACT =====
function launch_impact() {
    allow_x11
    docker run -it --rm \
        --privileged \
        -e DISPLAY=$DISPLAY \
        -e XILINXD_LICENSE_FILE=/downloads \
        -v /tmp/.X11-unix:/tmp/.X11-unix \
        -v /dev/bus/usb:/dev/bus/usb \
        -v ~/Downloads:/downloads \
        $IMAGE_NAME \
        bash -c "source /opt/Xilinx/14.7/ISE_DS/settings64.sh && impact"
}

# ===== Rebuild image from Dockerfile =====
function rebuild_image() {
    echo "[*] Rebuilding Docker image from $INSTALL_DIR..."
    docker build -t $IMAGE_NAME "$INSTALL_DIR"
    echo -e "${GREEN}[✓] Rebuild complete.${RESET}"
    read -p "Press Enter..."
}

# ===== Main Menu =====
function menu() {
    clear
    echo -e "${CYAN}${BOLD}=================================="
    echo -e "   Xilinx ISE Docker Manager"
    echo -e "==================================${RESET}"
    echo "  1) Open shell in container"
    echo "  2) Install ISE (xsetup)"
    echo "  3) Launch ISE GUI"
    echo "  4) Launch iMPACT (FPGA programmer)"
    echo "  5) Rebuild Docker image"
    echo "  6) Container manager / disk cleanup"
    echo "  7) Instructions"
    echo "  0) Exit"
    echo -e "${CYAN}${BOLD}==================================${RESET}"
    read -rp "  Select option: " choice

    case $choice in
        1) run_container ;;
        2) install_ise ;;
        3) launch_ise ;;
        4) launch_impact ;;
        5) rebuild_image ;;
        6) registry_menu ;;
        7) instructions ;;
        0) exit 0 ;;
        *) echo -e "${RED}Invalid option${RESET}"; sleep 2 ;;
    esac
}

while true; do
    menu
done
EOF

echo "[*] Making script executable..."
chmod +x "$SCRIPT_PATH"

echo "[*] Creating global shortcut: ise-docker"
sudo ln -sf "$SCRIPT_PATH" /usr/local/bin/ise-docker

echo ""
echo "========================================="
echo "✅ Setup Complete!"
echo "========================================="
echo ""
echo "Run from anywhere with:    ise-docker"
echo ""
