#!/bin/bash

INSTALL_DIR="$HOME/xilinx-docker"
SCRIPT_PATH="$INSTALL_DIR/run_ise.sh"

echo "[*] Creating ISE launcher script..."

cat > "$SCRIPT_PATH" << 'EOF'
#!/bin/bash

IMAGE_NAME="xilinx-ise"
CONTAINER_NAME="xilinx_ise_container"

function allow_x11() {
    echo "[*] Enabling X11 access..."
    xhost +local:docker >/dev/null 2>&1
}

function instructions() {
    clear
    echo "========================================="
    echo "     Xilinx ISE Docker - Instructions"
    echo "========================================="
    echo ""
    echo "FIRST TIME SETUP:"
    echo "  1) Run option 2 (Install ISE)"
    echo "  2) Follow GUI installer"
    echo ""
    echo "NORMAL USE:"
    echo "  - Option 3 → Launch ISE (design tools)"
    echo "  - Option 4 → iMPACT (program FPGA)"
    echo ""
    echo "NOTES:"
    echo "  - Board must be plugged in via USB"
    echo "  - Uses --privileged for JTAG access"
    echo "  - If GUI fails → check DISPLAY and xhost"
    echo ""
    read -p "Press Enter to continue..."
}

function run_container() {
    allow_x11
    docker run -it --rm \
        --name $CONTAINER_NAME \
        --privileged \
        -e DISPLAY=$DISPLAY \
        -v /tmp/.X11-unix:/tmp/.X11-unix \
        -v /dev/bus/usb:/dev/bus/usb \
        $IMAGE_NAME /bin/bash
}

function install_ise() {
    allow_x11
    docker run -it --rm \
        --privileged \
        -e DISPLAY=$DISPLAY \
        -v /tmp/.X11-unix:/tmp/.X11-unix \
        -v /dev/bus/usb:/dev/bus/usb \
        $IMAGE_NAME \
        bash -c "cd /home/xilinx/ise_installer && ./xsetup"
}

function launch_ise() {
    allow_x11
    docker run -it --rm \
        --privileged \
        -e DISPLAY=$DISPLAY \
        -v /tmp/.X11-unix:/tmp/.X11-unix \
        -v /dev/bus/usb:/dev/bus/usb \
        $IMAGE_NAME \
        bash -c "source /opt/Xilinx/14.7/ISE_DS/settings64.sh && ise"
}

function launch_impact() {
    allow_x11
    docker run -it --rm \
        --privileged \
        -e DISPLAY=$DISPLAY \
        -v /tmp/.X11-unix:/tmp/.X11-unix \
        -v /dev/bus/usb:/dev/bus/usb \
        $IMAGE_NAME \
        bash -c "source /opt/Xilinx/14.7/ISE_DS/settings64.sh && impact"
}

function rebuild_image() {
    echo "[*] Rebuilding Docker image..."
    docker build -t $IMAGE_NAME .
    read -p "Done. Press Enter..."
}

function menu() {
    clear
    echo "=================================="
    echo "   Xilinx ISE Docker Manager"
    echo "=================================="
    echo "1) Open shell"
    echo "2) Install ISE (xsetup)"
    echo "3) Launch ISE GUI"
    echo "4) Launch iMPACT (FPGA programmer)"
    echo "5) Rebuild Docker image"
    echo "6) Instructions"
    echo "0) Exit"
    echo "=================================="
    read -p "Select option: " choice

    case $choice in
        1) run_container ;;
        2) install_ise ;;
        3) launch_ise ;;
        4) launch_impact ;;
        5) rebuild_image ;;
        6) instructions ;;
        0) exit 0 ;;
        *) echo "Invalid option"; sleep 2 ;;
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
echo "Run it from anywhere with:"
echo ""
echo "    ise-docker"
echo ""
