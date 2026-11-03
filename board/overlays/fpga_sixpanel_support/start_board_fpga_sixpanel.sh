#!/bin/bash
set -euo pipefail
source /etc/profile.d/xrt_setup.sh
source /usr/local/share/pynq-venv/bin/activate
cd /home/xilinx/jupyter_notebooks/star_anise_fpga/overlays/fpga_sixpanel_support
exec python -u board_fpga_sixpanel.py
