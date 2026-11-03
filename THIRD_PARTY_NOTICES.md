# Third-party material and license boundary

The MIT license in `LICENSE` applies to original project-authored source and
documentation only. This repository also contains artifacts produced by AMD
Vivado/Vitis HLS and board support material. Their original notices remain in
place, and this repository does not grant additional rights to them.

| Location | Material | Note |
| --- | --- | --- |
| `camera_hdmi_720p_fpga_sixpanel_delivery/ip_repo/sixpanel_accel/` | Generated HLS IP and VHDL | Several files explicitly say “Copyright Xilinx/AMD. All Rights Reserved.” |
| `camera_hdmi_720p_fpga_sixpanel/ip_repo/` | HDMI compatibility IP package | Inspect each source header for its original terms before reuse. |
| `camera_hdmi_720p/board_files/` | PYNQ-Z1 board definition | Board support content is included to reproduce the target build. |
| `board/overlays/*.bit`, `board/overlays/*.hwh` | Vivado build outputs | Board-specific implementation artifacts, not separately MIT-licensed source. |

The original HLS C++ algorithm, project RTL, scripts, tests, and documentation
are the editable project sources. Anyone redistributing the complete package
should review the applicable AMD and board-support terms for generated and
third-party files. No ownership of those files is asserted here.
