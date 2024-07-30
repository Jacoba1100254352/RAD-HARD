#!/bin/bash

# Function to print an error message and exit
function error_exit {
    echo "$1" 1>&2
    exit 1
}

# Check if the OS is macOS Big Sur or later
OS_VERSION=$(sw_vers -productVersion)
MAJOR_VERSION=$(echo "$OS_VERSION" | cut -d'.' -f1)

if [ "$MAJOR_VERSION" -lt 11 ]; then
    error_exit "This script requires macOS Big Sur (11) or later. You are running macOS $OS_VERSION."
fi

# Variables for paths
BASE_DIR=$(pwd)
INCLUDE_DIR="${BASE_DIR}/include"
INSTALL_SCRIPTS_DIR="${BASE_DIR}/Install Scripts"

# Check if the required tar.gz files exist
if [ ! -f "${INCLUDE_DIR}/tcl8.6.13-src.tar.gz" ]; then
    error_exit "Tcl source file not found at ${INCLUDE_DIR}/tcl8.6.13-src.tar.gz"
fi

if [ ! -f "${INCLUDE_DIR}/tk8.6.13-src.tar.gz" ]; then
    error_exit "Tk source file not found at ${INCLUDE_DIR}/tk8.6.13-src.tar.gz"
fi

# Install Homebrew if not installed
if ! command -v brew &> /dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || error_exit "Failed to install Homebrew."
fi

# Install Xquartz
echo "Installing Xquartz..."
brew install --cask xquartz || error_exit "Failed to install Xquartz."

# Install required packages
echo "Installing required packages..."
brew install cairo ngspice libxpm macvim dbus jpeg || error_exit "Failed to install required packages."
brew services start dbus

# Set environment variables for JPEG
export LDFLAGS="-L/usr/local/opt/jpeg/lib"
export CPPFLAGS="-I/usr/local/opt/jpeg/include"

# Add environment variables to shell configuration (do not run as root)
echo "Updating shell configuration..."
SHELL_CONFIG=""
if [ -f ~/.bashrc ]; then
    SHELL_CONFIG="$HOME/.bashrc"
elif [ -f ~/.zshrc ]; then
    SHELL_CONFIG="$HOME/.zshrc"
else
    echo "Neither ~/.bashrc nor ~/.zshrc found. The following are being run manually:
export DYLD_LIBRARY_PATH=\"/usr/local/opt/tcl-tk/lib:/opt/X11/lib\"
export PATH=\"/Users/$(whoami)/opt/xschem/bin:\$PATH\"
export DISPLAY=:0"
    echo "Please add the above line to .bashrc or .zshrc when possible"
    export DYLD_LIBRARY_PATH="/usr/local/opt/tcl-tk/lib:/opt/X11/lib"
    export PATH="/Users/$(whoami)/opt/xschem/bin:$PATH"
    export DISPLAY=:0
fi

if [ -n "$SHELL_CONFIG" ]; then
    if ! grep -q 'export DYLD_LIBRARY_PATH="/usr/local/opt/tcl-tk/lib:/opt/X11/lib"' "$SHELL_CONFIG"; then
        echo 'export DYLD_LIBRARY_PATH="/usr/local/opt/tcl-tk/lib:/opt/X11/lib"' >> "$SHELL_CONFIG"
    fi

    if ! grep -q 'export PATH="/Users/$(whoami)/opt/xschem/bin:$PATH"' "$SHELL_CONFIG"; then
        echo 'export PATH="/Users/$(whoami)/opt/xschem/bin:$PATH"' >> "$SHELL_CONFIG"
    fi

    if ! grep -q 'export DISPLAY=:0' "$SHELL_CONFIG"; then
        echo 'export DISPLAY=:0' >> "$SHELL_CONFIG"
    fi

    if ! grep -q 'export DYLD_LIBRARY_PATH=/opt/local/lib/postgresql94:/usr/lib' "$SHELL_CONFIG"; then
        echo 'export DYLD_LIBRARY_PATH=/opt/local/lib/postgresql94:/usr/lib' >> "$SHELL_CONFIG"
    fi
fi

# Remove any existing files in /usr/local/opt/tcl-tk
echo "Cleaning up previous Tcl and Tk installations..."
rm -rf /usr/local/opt/tcl-tk/*

# Extract and compile Tcl
echo "Compiling Tcl..."
mkdir -p /usr/local/opt/tcl-tk
tar -xzf "${INCLUDE_DIR}/tcl8.6.13-src.tar.gz" -C /tmp || error_exit "Failed to extract Tcl."
cd /tmp/tcl8.6.13/unix || error_exit "Tcl source directory not found."
./configure --prefix=/usr/local/opt/tcl-tk || error_exit "Failed to configure Tcl."
make || error_exit "Failed to make Tcl."
make install || error_exit "Failed to install Tcl."

# Extract and compile Tk
echo "Compiling Tk..."
tar -xzf "${INCLUDE_DIR}/tk8.6.13-src.tar.gz" -C /tmp || error_exit "Failed to extract Tk."
cd /tmp/tk8.6.13/unix || error_exit "Tk source directory not found."
./configure --prefix=/usr/local/opt/tcl-tk --with-tcl=/usr/local/opt/tcl-tk/lib --with-x --x-includes=/opt/X11/include --x-libraries=/opt/X11/lib || error_exit "Failed to configure Tk."
make || error_exit "Failed to make Tk."
make install || error_exit "Failed to install Tk."

# Symlink libtk
sudo ln -s /usr/local/opt/tcl-tk/lib/libtk8.6.dylib /opt/X11/lib/libtk8.6.dylib # || error_exit "Failed to symlink libtk."

# Clone xschem
echo "Cloning xschem repository..."
git clone https://github.com/StefanSchippers/xschem.git /tmp/xschem || error_exit "Failed to clone xschem repository."
cd /tmp/xschem || error_exit "Failed to navigate to xschem directory."
git checkout 973d01f || error_exit "Failed to checkout the specific commit for release 3.4.5."

# Configure xschem
echo "Configuring xschem..."
./configure --prefix="/Users/$(whoami)/opt/xschem" || error_exit "Failed to configure xschem."

# Modify Makefile.conf
echo "Modifying Makefile.conf..."
sed -i.bak 's|CFLAGS=.*|CFLAGS=-std=c99 -I/opt/X11/include -I/opt/X11/include/cairo -I/usr/local/opt/tcl-tk/include -I/usr/local/include -I/usr/local/opt/jpeg/include -O2|' Makefile.conf
sed -i.bak 's|LDFLAGS=.*|LDFLAGS=-L/opt/X11/lib -L/usr/local/opt/tcl-tk/lib -L/usr/local/lib -L/usr/local/opt/jpeg/lib -lm -lcairo -ljpeg -lX11 -lXrender -lxcb -lxcb-render -lX11-xcb -lXpm -ltcl8.6 -ltk8.6|' Makefile.conf

# Build xschem
echo "Building xschem..."
make clean || error_exit "Failed to clean xschem build."
make || error_exit "Failed to build xschem."

# Install xschem
echo "Installing xschem..."
make install || error_exit "Failed to install xschem."

echo "xschem installation completed successfully."

# Define the DMG file path
DMG_FILE="include/analog_flavor_eval_osx_2024_06_24.dmg"

# Attach the DMG file and get the mount point
MOUNT_POINT=$(hdiutil attach "$DMG_FILE" | grep "/Volumes/" | awk '{for (i=3; i<=NF; i++) printf "%s ", $i; print ""}' | sed 's/ *$//')

# Check if the DMG file was mounted successfully
if [ -z "$MOUNT_POINT" ]; then
    error_exit "Failed to mount DMG file."
fi

echo "DMG mounted at: $MOUNT_POINT"

# List contents of the mounted volume to identify the correct application path
echo "Contents of $MOUNT_POINT:"
ls "$MOUNT_POINT"

# Define the expected paths for the application
APP_PATH="$MOUNT_POINT/BeSpiceWave.app"

# Copy the application or files to the Applications folder (or any other desired location)
if [ -d "$APP_PATH" ]; then
    cp -R "$APP_PATH" /Applications/ || error_exit "Failed to copy BeSpiceWave.app to /Applications"
else
    error_exit "BeSpiceWave.app not found in mounted volume."
fi

# Unmount the DMG file
hdiutil detach "$MOUNT_POINT"

# Check if the unmount was successful
if [ $? -ne 0 ]; then
    error_exit "Failed to unmount DMG file."
fi

echo "BeSpice Wave installation completed successfully."