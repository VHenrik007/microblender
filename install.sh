#!/bin/bash

# Colors for better visibility
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Detect OS and package manager
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        if command -v apt-get >/dev/null; then
            PKG_MANAGER="apt-get"
        elif command -v dnf >/dev/null; then
            PKG_MANAGER="dnf"
        elif command -v pacman >/dev/null; then
            PKG_MANAGER="pacman"
        else
            echo -e "${RED}Unsupported package manager. Please install dependencies manually.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Cannot detect OS. Please install dependencies manually.${NC}"
        exit 1
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check dependencies with version requirements
check_dependencies() {
    setup_clipboard_tools

    local missing_deps=()
    declare -A deps=(
        ["curl"]="curl --version"
        ["git"]="git --version"
        ["python3"]="python3 --version"
        ["pip3"]="pip3 --version"
    )

    echo -e "${GREEN}Checking dependencies...${NC}"
    for dep in "${!deps[@]}"; do
        if ! command_exists "$dep"; then
            missing_deps+=("$dep")
        else
            echo -e "Found ${GREEN}$dep${NC}: $(${deps[$dep]} 2>&1 | head -n1)"
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RED}Missing required dependencies: ${missing_deps[*]}${NC}"
        echo -e "Installing missing dependencies..."

        case $PKG_MANAGER in
            "apt-get")
                sudo apt-get update && sudo apt-get install -y "${missing_deps[@]}"
                ;;
            "dnf")
                sudo dnf install -y "${missing_deps[@]}"
                ;;
            "pacman")
                sudo pacman -Syu --noconfirm "${missing_deps[@]}"
                ;;
        esac
    fi
}

# Function to check and install clipboard tools
setup_clipboard_tools() {
    echo -e "${GREEN}Setting up clipboard tools...${NC}"

    # Check display server type
    if [ -n "$WAYLAND_DISPLAY" ]; then
        echo "Detected Wayland display server"
        if ! command_exists wl-copy; then
            echo "Installing Wayland clipboard tools..."
            case $PKG_MANAGER in
                "apt-get")
                    sudo apt-get install -y wl-clipboard
                    ;;
                "dnf")
                    sudo dnf install -y wl-clipboard
                    ;;
                "pacman")
                    sudo pacman -S --noconfirm wl-clipboard
                    ;;
            esac
        else
            echo -e "Found ${GREEN}wl-clipboard${NC}"
        fi
    elif [ -n "$DISPLAY" ]; then
        echo "Detected X11 display server"
        local need_xclip=false
        local need_xsel=false

        if ! command_exists xclip; then
            need_xclip=true
        else
            echo -e "Found ${GREEN}xclip${NC}"
        fi

        if ! command_exists xsel; then
            need_xsel=true
        else
            echo -e "Found ${GREEN}xsel${NC}"
        fi

        if [ "$need_xclip" = true ] || [ "$need_xsel" = true ]; then
            echo "Installing X11 clipboard tools..."
            case $PKG_MANAGER in
                "apt-get")
                    [ "$need_xclip" = true ] && sudo apt-get install -y xclip
                    [ "$need_xsel" = true ] && sudo apt-get install -y xsel
                    ;;
                "dnf")
                    [ "$need_xclip" = true ] && sudo dnf install -y xclip
                    [ "$need_xsel" = true ] && sudo dnf install -y xsel
                    ;;
                "pacman")
                    [ "$need_xclip" = true ] && sudo pacman -S --noconfirm xclip
                    [ "$need_xsel" = true ] && sudo pacman -S --noconfirm xsel
                    ;;
            esac
        fi
    else
        echo -e "${YELLOW}No display server detected. Clipboard functionality may be limited.${NC}"
    fi
}

# Function to setup udev rules for Microbit
setup_udev_rules() {
    local rules_file="/etc/udev/rules.d/69-microbit.rules"
    local rules_content='ACTION!="add|change", GOTO="microbit_rules_end"
SUBSYSTEM=="usb", ATTR{idVendor}=="0d28", ATTR{idProduct}=="0204", TAG+="uaccess"
LABEL="microbit_rules_end"'

    echo -e "${GREEN}Setting up udev rules for Microbit...${NC}"

    if [ -f "$rules_file" ]; then
        if grep -q "microbit_rules_end" "$rules_file"; then
            echo -e "${GREEN}Microbit udev rules already installed${NC}"
            return
        fi
    fi

    if ! sudo -n true 2>/dev/null; then
        echo -e "${YELLOW}Sudo access required to install udev rules${NC}"
    fi

    echo "$rules_content" | sudo tee "$rules_file"
    sudo udevadm control --reload
    sudo udevadm trigger
}

# Function to setup Python environment
setup_python_env() {
    echo -e "${GREEN}Setting up Python virtual environment...${NC}"

    if [ ! -d ".venv" ]; then
        python3 -m venv .venv
        echo -e "${GREEN}Created new virtual environment${NC}"
    else
        echo -e "${YELLOW}Virtual environment already exists${NC}"
    fi

    # Create requirements.txt if it doesn't exist
    if [ ! -f "requirements.txt" ]; then
        echo -e "numpy\nmatplotlib\n" > requirements.txt
    fi

    # Activate virtual environment and install dependencies
    source .venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt

    # Create activation helper script
    cat > activate_env.sh << 'EOF'
#!/bin/bash
source .venv/bin/activate
echo "Python virtual environment activated. Use 'deactivate' to exit."
EOF
    chmod +x activate_env.sh
}

# Function to install Rust toolchain
install_rust_toolchain() {
    echo -e "${GREEN}Installing Rust and required tools...${NC}"

    if ! command_exists rustc; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    else
        echo -e "${GREEN}Rust is already installed${NC}"
        rustup update
    fi

    rustup component add llvm-tools
    rustup target add thumbv7em-none-eabihf
    cargo install cargo-binutils cargo-embed --force
}

# Main installation process
main() {
    echo -e "${GREEN}Starting complete installation process...${NC}"

    detect_os
    check_dependencies

    # Only setup udev rules on Linux
    if [[ "$OS" == *"Linux"* ]]; then
        setup_udev_rules
    else
        echo -e "${YELLOW}Skipping udev rules setup (non-Linux OS detected)${NC}"
    fi

    install_rust_toolchain
    setup_python_env

    echo -e "\n${GREEN}Installation complete! To get started:${NC}"
    echo -e "1. Unplug and replug your Microbit if it's connected"
    echo -e "2. See README.md for full usage instructions"
    echo -e "3. Use `./run.sh` to start everything"
    echo -e "4. Move the microbit, and behold the visuals! 🚀"
}

# Run main installation
main