# Microbit Motion Control for Blender

This project demonstrates the integration of embedded systems with 3D visualization, using a Microbit v2 microcontroller to control objects in Blender through motion sensing. It serves as both an educational resource for learning embedded Rust programming and a practical example of sensor data visualization.

## Project Overview

The system captures motion data from the Microbit's accelerometer and visualizes it in two ways:

1. A real-time 3D object controller in Blender
2. A more physical visualization using Python's Matplotlib, showcasing vector components.

As this is a **hobby/learning** project. Contributions and improvements are warmly welcomed!

## Prerequisites

- An Ubuntu/Debian-based Linux system
  - Other Linux distributions may work but are not officially tested yet
- A [Microbit v2](https://microbit.org/buy/where/?version=microbitV2) microcontroller (v1 is not supported)
- [Blender](https://www.blender.org/download/) (tested with version 4.3+)
- A USB connection to the Microbit
- Python 3.8 or newer

## Installation

1. Clone this repository:

   ```bash
   git clone https://github.com/VHenrik007/microblender
   cd microblender
   ```

2. Run the installation script:

   ```bash
   chmod +x install.sh
   sudo ./install.sh
   ```

The script will install:

- Required system packages (clipping tools, `curl`, etc...)
- Rust and embedded development tools (`cargo-embed`, `llvm-tools`, and our target)
- Python dependencies in a virtual environment (`python-venv` and then `matplotlib`)
- Microbit udev rules for USB access

Default values:

- Networking
- - Host: 127.0.0.1
- - Blender: 65432
- - Matplotlib: 65434
- Serial:
- - Baud rate: 115200 (set in the firmware and the bridge)
- - Output data rate: 50Hz (set in the firmware and visualization scripts)

## Usage

There are two visualizations currently. One with Blender, and one using Matplotlib in Python. The latter could be changed to something more performant in the future.

### Basic Usage

1. Connect your Microbit via USB
2. Run the project with your preferred visualization:

   ```bash
   ./run.sh --blender          # For Blender visualization
   ./run.sh --visualizer       # For Python visualization
   ./run.sh -b -v              # For both visualizations
   ```

### Blender Setup

When using the Blender visualization:

1. Open Blender
2. Switch to the Scripting workspace
3. Create a new text file
4. Paste the contents of `blender.py` (automatically copied to clipboard by the run script)
5. Click "Run Script"

You should see the default cube that responds to your Microbit's movement.

## System components

```ascii
┌─────────┐    Serial     ┌────────┐    TCP/IP     ┌──────────────┐
│ Microbit├───────────────┤ Bridge ├──────────────►│ Visualizers  │
└─────────┘    (USB)      └────────┘    (Local)    └──────────────┘
```

- `board/`: Rust firmware for the Microbit
- `bridge/`: Rust-based data forwarder
- Visualization Components:
  - `blender.py`: 3D object control
  - `visualization.py`: Direct visualiation of force vectors

## Troubleshooting Guide

### Common Issues and Solutions

#### Permission Errors

If you encounter permission issues:

1. Unplug and replug the Microbit
2. Simply retry building the board. Sometimes some ARM issue occurs that goes away for the second attempt.
3. Verify udev rules: `ls -l /dev/ttyACM0`

#### Connection Problems

If the visualizations aren't receiving data:

1. Check the Microbit connection: `ls /dev/ttyACM*`
2. Verify no other program is using the port: `lsof /dev/ttyACM0`

#### Building and Running Individual Components

Sometimes it's helpful to run components separately in their own terminal windows/tabs for debugging. From the project root:

1. Flash the Microbit:

   ```bash
   cd board
   cargo embed --features v2 --target thumbv7em-none-eabihf
   ```

2. Run the bridge (in a new terminal):

   ```bash
   cd bridge
   cargo run -- --blender --visualizer
   ```

3. Start Python visualization:

   ```bash
   source .venv/bin/activate
   python visualization.py
   ```

## Contributing

Contributions are welcome! I'm planning on enhancing the actual sensor logic itself by including the magnetometer later on for example, and introducing algorithms/numerical methods for enhanced motion stability, etc.
I'd be especially thankful for **cross-platform validations**, and more robust **installation/running and networking solutions**, even if that includes using containerization. I'm also open for additional tooling and potential CI/CD proposals.
Improvements on **more insightful visualizations** and data processing are also welcomed.

Please feel free to:

- Open issues for bugs or feature requests
- Submit pull requests with improvements

## Learning Resources

This project builds upon several excellent resources:

- [Rust Embedded Discovery Book](https://docs.rust-embedded.org/discovery/microbit/)
- [Microbit v2 Technical Documentation](https://tech.microbit.org/hardware/)
- [Blender Python API Documentation](https://docs.blender.org/api/current/info_quickstart.html)

## License

This project is released under the MIT License. See [LICENSE](LICENSE) for details.

Component Licenses:

- Microbit firmware: Based on Discovery book examples (MIT)
- Python visualization: Uses Matplotlib (PSF License)
- Blender integration: Uses Blender Python API (GPL)
