#!/bin/bash

set -e

# ===== Colours =====
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
RESET='\033[0m'

# ===== Paths =====
TAR_SRC="/home/mark/Installs/Spartan6/Xilinx_ISE_DS_Lin_14.7_1015_1.tar"
TAR_DEST="/home/mark/xilinx-docker"
INSTALLER_DIR="$TAR_DEST/Xilinx_ISE_14.7"

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
    sudo apt install -y docker.io
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
        echo -e "${RED}ERROR: Extraction failed${RESET}"
        exit 1
    fi

    if [ "$EXTRACTED" != "$INSTALLER_DIR" ]; then
        mv "$EXTRACTED" "$INSTALLER_DIR"
    fi

    echo -e "${GREEN}Installer ready at:${RESET} $INSTALLER_DIR"
}

# ===== Create Docker Setup =====
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

RUN useradd -ms /bin/bash xilinx

RUN mkdir -p /root/.Xilinx/xinstall && \
    touch /root/.Xilinx/xinstall/xinstall.log

COPY Xilinx_ISE_14.7 /home/xilinx/ise_installer
COPY ise_config.txt /home/xilinx/ise_installer/ise_config.txt

USER root

RUN chmod +x /home/xilinx/ise_installer/xsetup

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

    echo -e "${GREEN}Dockerfile created${RESET}"
}

# ===== Build Docker =====
build_docker() {
    echo -e "${GREEN}Building Docker image...${RESET}"
    cd "$TAR_DEST"

    docker build -t xilinx-ise . 2>&1 | tee build.log

    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        echo -e "${RED}Build failed. See build.log${RESET}"
        exit 1
    fi

    echo -e "${GREEN}Docker build complete!${RESET}"
}

# ===== Shutdown Prompt =====
shutdown_prompt() {
    echo ""
    read -p "Shutdown system now? (y/n): " confirm

    if [[ $confirm =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Shutting down...${RESET}"
        sudo shutdown -h now
    else
        echo -e "${GREEN}Done. No shutdown.${RESET}"
    fi
}

# ===== MAIN =====
main() {
    echo -e "${GREEN}Requesting sudo access...${RESET}"
    sudo -v

    keep_sudo_alive

    sudo rm -rf "$TAR_DEST"

    do_update
    extract_installer
    make_directories
    build_docker

    shutdown_prompt
}

main
