"""PYNQ runner for the PL six-panel HLS design.

The PL performs all six image panels, segmentation, radial-tip detection and
the >=10/<10 class decision. Python only moves frame addresses, starts the
frame accelerator and feeds its output buffer to VDMA for HDMI scanout.
"""
from __future__ import annotations

import asyncio
from pathlib import Path
import sys
from time import monotonic, sleep

import numpy as np
from pynq import MMIO, Overlay, allocate
from pynq.lib.video import VideoMode
from pynq.lib.video.dma import AxiVDMA

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from ov5640_vga_720p_hdmi import (  # noqa: E402
    camera_reset_and_check,
    configure_camera_standby,
    reset_vdma,
    write_reg,
)

OVERLAY_PATH = "/home/xilinx/jupyter_notebooks/star_anise_fpga/overlays/camera_hdmi_720p_fpga_sixpanel.bit"
CAPTURE_WIDTH, CAPTURE_HEIGHT = 640, 480
DISPLAY_WIDTH, DISPLAY_HEIGHT = 1280, 640
HLS_AP_CTRL = 0x00
HLS_CAMERA_LO, HLS_CAMERA_HI = 0x10, 0x14
HLS_MOSAIC_LO, HLS_MOSAIC_HI = 0x1C, 0x20
HLS_HISTORY_LO, HLS_HISTORY_HI = 0x28, 0x2C
HLS_WORK_LO, HLS_WORK_HI = 0x34, 0x38
HLS_CLEAR_HISTORY = 0x40


class _PollingInterrupt:
    """Compatibility shim for PYNQ's VDMA driver when interrupts are absent."""
    def wait(self):
        return None

    def is_pending(self):
        return True

    def clear(self):
        return None


def _write_address(mmio: MMIO, low_offset: int, high_offset: int, address: int) -> None:
    mmio.write(low_offset, address & 0xFFFFFFFF)
    mmio.write(high_offset, (address >> 32) & 0xFFFFFFFF)


def main() -> None:
    asyncio.set_event_loop(asyncio.new_event_loop())
    print(f"Loading PL six-panel overlay: {OVERLAY_PATH}", flush=True)
    overlay = Overlay(OVERLAY_PATH)
    if not overlay.ip_dict["axi_vdma_0"].get("interrupts"):
        AxiVDMA.s2mm_introut = _PollingInterrupt()
        AxiVDMA.mm2s_introut = _PollingInterrupt()

    reset_gpio = overlay.axi_gpio_0.channel1
    iic = overlay.axi_iic_0
    dma = overlay.axi_vdma_0
    vtc = overlay.v_tc_0
    camera_status = overlay.axi_gpio_status
    camera_diag = overlay.axi_gpio_camera_diag
    video_status = overlay.axi_gpio_video_status
    hls_info = overlay.ip_dict["sixpanel_accel_0"]
    hls = MMIO(hls_info["phys_addr"], 0x1000)

    capture_mode = VideoMode(CAPTURE_WIDTH, CAPTURE_HEIGHT, 16, 60)
    display_mode = VideoMode(DISPLAY_WIDTH, DISPLAY_HEIGHT, 16, 60)
    capture_frames = []
    camera_snapshot = None
    mosaic_staging = None
    fill_history = None
    panel_workspace = None
    last_capture_index = None
    frame_count = 0
    interval_start = monotonic()

    try:
        camera_reset_and_check(reset_gpio, iic)
        configure_camera_standby(iic)
        reset_vdma(dma)
        dma.readchannel.mode = capture_mode
        dma.writechannel.mode = display_mode
        dma.readchannel.start()
        dma.writechannel.start()
        capture_frames = dma.readchannel._frames

        fill_history = allocate(shape=(96_000,), dtype=np.uint32)
        panel_workspace = allocate(shape=(900_000,), dtype=np.uint32)
        camera_snapshot = allocate(shape=(CAPTURE_WIDTH * CAPTURE_HEIGHT,), dtype=np.uint16)
        # Keep the HLS destination outside the MM2S frame ring. The kernel can
        # take hundreds of milliseconds, so writing directly into a scanout
        # frame lets VDMA show a cleared or partially rendered mosaic.
        mosaic_staging = allocate(
            shape=(DISPLAY_WIDTH * DISPLAY_HEIGHT,), dtype=np.uint16
        )
        fill_history[:] = 0
        panel_workspace[:] = 0
        mosaic_staging[:] = 0
        fill_history.flush()
        panel_workspace.flush()
        mosaic_staging.flush()

        write_reg(iic, 0x4202, 0x00)
        write_reg(iic, 0x3008, 0x02)
        sleep(0.8)
        vtc.write(0x0000, 0x03FDEF07)
        sleep(0.5)

        _write_address(hls, HLS_HISTORY_LO, HLS_HISTORY_HI, int(fill_history.device_address))
        _write_address(hls, HLS_WORK_LO, HLS_WORK_HI, int(panel_workspace.device_address))
        hls.write(HLS_CLEAR_HISTORY, 1)
        hls.write(HLS_CLEAR_HISTORY, 0)
        print("PL processing active; BTN0 toggles the latched class on HDMI.", flush=True)

        while True:
            capture_count = len(capture_frames)
            capture_index = (dma.readchannel.activeframe + capture_count - 2) % capture_count
            if capture_index == last_capture_index:
                sleep(0.002)
                continue

            camera_frame = capture_frames[capture_index]
            camera_frame.invalidate()
            camera_snapshot[:] = np.asarray(camera_frame).view(np.uint16).reshape(-1)
            camera_snapshot.flush()

            _write_address(hls, HLS_CAMERA_LO, HLS_CAMERA_HI, int(camera_snapshot.device_address))
            _write_address(hls, HLS_MOSAIC_LO, HLS_MOSAIC_HI, int(mosaic_staging.device_address))
            started = monotonic()
            hls.write(HLS_AP_CTRL, 1)
            while (hls.read(HLS_AP_CTRL) & 0x2) == 0:
                if monotonic() - started > 3.0:
                    raise TimeoutError("sixpanel_accel did not assert ap_done within 3 seconds")
                sleep(0.001)

            mosaic_staging.invalidate()
            output_frame = dma.writechannel.newframe()
            output_frame.view(np.uint16).reshape(
                DISPLAY_HEIGHT, DISPLAY_WIDTH
            )[:] = mosaic_staging.reshape(DISPLAY_HEIGHT, DISPLAY_WIDTH)
            output_frame.flush()
            # writeframe waits for the VDMA frame boundary and transfers
            # ownership, so a buffer is never modified while it is scanned.
            dma.writechannel.writeframe(output_frame)
            last_capture_index = capture_index
            frame_count += 1
            if frame_count % 5 == 0:
                elapsed = max(1e-6, monotonic() - interval_start)
                cam0 = camera_status.channel1.read()
                cam1 = camera_status.channel2.read()
                diag0 = camera_diag.channel1.read()
                vid0 = video_status.channel1.read()
                vid1 = video_status.channel2.read()
                camera_pixels = cam0 >> 13
                camera_lines = (cam0 >> 3) & 0x3FF
                min_line = (diag0 >> 11) & 0x7FF
                max_line = diag0 & 0x7FF
                camera_overflows = cam1 >> 16
                camera_frames = cam1 & 0xFFFF
                video_underflows = vid1 >> 16
                print(
                    f"PL frames={frame_count} update_fps={5.0 / elapsed:.2f} "
                    f"last_kernel_ms={(monotonic() - started) * 1000:.1f} "
                    f"DVP={camera_lines}x{camera_pixels} phase_err={(cam0 >> 2) & 1} "
                    f"fifo_ovf={camera_overflows} src_frames={camera_frames} "
                    f"line_px={min_line}..{max_line} "
                    f"HDMI_frames={vid0 & 0xFFFF} underflows={video_underflows} "
                    f"sync_err={(vid1 >> 3) & 1}",
                    flush=True,
                )
                interval_start = monotonic()

    finally:
        try:
            dma.stop()
        except Exception:
            pass
        if fill_history is not None:
            fill_history.freebuffer()
        if panel_workspace is not None:
            panel_workspace.freebuffer()
        if camera_snapshot is not None:
            camera_snapshot.freebuffer()
        if mosaic_staging is not None:
            mosaic_staging.freebuffer()
        for frame in capture_frames:
            try:
                frame.freebuffer()
            except Exception:
                pass


if __name__ == "__main__":
    main()
