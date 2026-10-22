#!/bin/bash
# Double-click: builds Kirpik, installs it to /Applications and launches it.
cd "$(dirname "$0")"
./build.sh --install && echo && echo "Done. You can close this window."
