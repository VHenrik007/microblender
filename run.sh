#!/bin/bash

# Colors for visibility
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
MICROBIT_PORT="/dev/ttyACM0"
MICROBIT_TIMEOUT=30  # seconds
BRIDGE_STARTUP_TIMEOUT=5  # seconds
# Add to the argument parsing section:
FORCE_FLASH=false

show_help() {
    echo -e "${BLUE}Microbit Visualization Runner${NC}"
    echo -e "\nThis script manages the visualization pipeline for Microbit data."
    echo -e "It can run either the Blender visualization, Python visualizer, or both simultaneously."
    echo -e "\n${BLUE}Usage: $0 [options]${NC}"
    echo -e "\nOptions:"
    echo "  -f, --flash       Force flash the Microbit firmware"
    echo "  -b, --blender     Enable Blender visualization (copies script to clipboard)"
    echo "  -v, --visualizer  Enable Python visualizer (runs in background)"
    echo "  -p, --port PATH   Specify Microbit port (default: /dev/ttyACM0)"
    echo "  -h, --help        Show this help message"
    echo -e "\nExamples:"
    echo "  $0 -v             Run Python visualizer only"
    echo "  $0 -b -v          Run both visualizations"
    echo "  $0 -p /dev/ttyACM1 -v   Use specific port"
}

handle_error() {
    local error_msg=$1
    local exit_code=${2:-1}
    echo -e "\n${RED}Error: $error_msg${NC}"
    cleanup
    exit $exit_code
}

flash_microbit() {
    echo -e "\n${BLUE}Preparing to flash Microbit...${NC}"

    # Verify board directory exists
    if [ ! -d "board" ]; then
        handle_error "Could not find 'board' directory. Are you in the project root?"
    fi

    # Navigate to board directory
    cd board || handle_error "Could not access 'board' directory"

    echo -e "${BLUE}Building and flashing firmware...${NC}"
    if ! cargo embed --features v2 --target thumbv7em-none-eabihf; then
        cd - > /dev/null
        handle_error "Flashing failed. Please check:\n- Is the Microbit connected?\n- Do you have the correct permissions?\n- Is the firmware code valid?"
    fi

    echo -e "${GREEN}Firmware successfully flashed to Microbit${NC}"
    cd - > /dev/null

    # Give the device time to reset and enumerate
    echo -e "${BLUE}Waiting for Microbit to reset...${NC}"
    sleep 2
}

handle_flashing() {
    local force_flash=$1

    if [ "$force_flash" = true ]; then
        flash_microbit
    else
        while true; do
            read -p "Do you want to flash the Microbit? (y/N/q): " response
            case $response in
                [Yy]* )
                    flash_microbit
                    break
                    ;;
                [Nn]* )
                    echo -e "${BLUE}Skipping firmware flash${NC}"
                    break
                    ;;
                [Qq]* )
                    echo -e "${BLUE}Exiting at user request${NC}"
                    exit 0
                    ;;
                * )
                    echo -e "${BLUE}Skipping firmware flash${NC}"
                    break
                    ;;
            esac
        done
    fi
}

start_microbit() {
    local port=$1
    local timeout=$2
    local start_time=$(date +%s)

    handle_flashing $3

    echo -n "Waiting for Microbit"
    while true; do
        if [ -c "$port" ]; then
            echo -e "\n${GREEN}Microbit detected at $port${NC}"
            sleep 1  # Give the device time to initialize
            return 0
        fi

        if [ $(($(date +%s) - start_time)) -gt $timeout ]; then
            handle_error "Microbit not detected after ${timeout}s. Please check:\n- Is it connected?\n- Do you have the correct permissions?\n- Is the port correct? (current: $port)"
        fi

        echo -n "."
        sleep 0.5
    done
}

# Copy Blender script to clipboard
copy_to_clipboard() {
    local script_path=$1

    if [ ! -f "$script_path" ]; then
        handle_error "Blender script not found at: $script_path"
    fi

    echo -e "${BLUE}Attempting to copy Blender script to clipboard...${NC}"

    if [ -n "$WAYLAND_DISPLAY" ]; then
        if command -v wl-copy &> /dev/null; then
            cat "$script_path" | wl-copy
            echo -e "${GREEN}Script copied to clipboard (Wayland)${NC}"
            return 0
        fi
    elif [ -n "$DISPLAY" ]; then
        if command -v xclip &> /dev/null; then
            cat "$script_path" | xclip -selection clipboard
            echo -e "${GREEN}Script copied to clipboard (X11 - xclip)${NC}"
            return 0
        elif command -v xsel &> /dev/null; then
            cat "$script_path" | xsel --clipboard
            echo -e "${GREEN}Script copied to clipboard (X11 - xsel)${NC}"
            return 0
        fi
    fi

    echo -e "${YELLOW}Could not copy to clipboard automatically. Manual copy required:${NC}"
    echo -e "${YELLOW}Please copy the contents of: $script_path${NC}"
    read -p "Press Enter once you've copied the script..."
}

# Cleanup function to stop processes
cleanup() {
    echo -e "\n${GREEN}Cleaning up processes...${NC}"

    if [ -n "$VIZ_PID" ]; then
        echo "Stopping visualizer (PID: $VIZ_PID)"
        kill $VIZ_PID 2>/dev/null || true
        wait $VIZ_PID 2>/dev/null || true
    fi

    if [ -n "$BRIDGE_PID" ]; then
        echo "Stopping bridge (PID: $BRIDGE_PID)"
        kill $BRIDGE_PID 2>/dev/null || true
        wait $BRIDGE_PID 2>/dev/null || true
    fi

    echo -e "${GREEN}Cleanup complete${NC}"
}

# Parse command line arguments
BLENDER=false
VISUALIZER=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--flash)
            FORCE_FLASH=true
            shift
            ;;
        -b|--blender)
            BLENDER=true
            shift
            ;;
        -v|--visualizer)
            VISUALIZER=true
            shift
            ;;
        -p|--port)
            MICROBIT_PORT="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            handle_error "Unknown option: $1\nUse -h or --help for usage information"
            ;;
    esac
done

# Validate arguments
if ! $BLENDER && ! $VISUALIZER; then
    handle_error "You must specify at least one visualization target (-b and/or -v)\nUse -h or --help for usage information"
fi

# Set up trap for cleanup
trap cleanup SIGINT SIGTERM EXIT

start_microbit "$MICROBIT_PORT" "$MICROBIT_TIMEOUT" "$FORCE_FLASH"

# Set up visualizations
BRIDGE_ARGS="--port $MICROBIT_PORT"

if $BLENDER; then
    echo -e "\n${BLUE}Setting up Blender visualization...${NC}"
    copy_to_clipboard "blender.py"
    BRIDGE_ARGS="$BRIDGE_ARGS --blender"
fi

if $VISUALIZER; then
    echo -e "\n${BLUE}Setting up Python visualizer...${NC}"
    if ! source .venv/bin/activate 2>/dev/null; then
        handle_error "Python virtual environment not found.\nPlease run the installation script first."
    fi

    echo -e "${GREEN}Starting visualizer...${NC}"
    python visualization.py &
    VIZ_PID=$!

    # Check if visualizer started successfully
    sleep 1
    if ! kill -0 $VIZ_PID 2>/dev/null; then
        handle_error "Visualizer failed to start"
    fi

    BRIDGE_ARGS="$BRIDGE_ARGS --visualizer"
fi

# Start bridge program
echo -e "\n${BLUE}Starting bridge program...${NC}"
cd bridge || handle_error "Could not find bridge directory"
echo -e "Running with arguments: $BRIDGE_ARGS"

cargo run -- $BRIDGE_ARGS &
BRIDGE_PID=$!

# Wait for bridge to start
sleep $BRIDGE_STARTUP_TIMEOUT
if ! kill -0 $BRIDGE_PID 2>/dev/null; then
    handle_error "Bridge program failed to start or got terminated"
fi

# Wait for bridge program to complete
wait $BRIDGE_PID