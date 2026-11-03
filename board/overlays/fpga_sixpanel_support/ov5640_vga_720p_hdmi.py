#!/usr/bin/env python3
"""Start the PYNQ-Z1 OV5640 VGA-to-720p-HDMI overlay and print diagnostics.

The sensor settings are a static userspace translation of the Linux mainline
OV5640 DVP init/low-resolution/VGA path.  The board must provide the camera's
own reference clock; this design deliberately has no cam_xclk/P0 connection.
"""

import argparse
import asyncio
import hashlib
from datetime import datetime
from pathlib import Path
from time import sleep, monotonic

from pynq import Overlay
from pynq.lib.video import VideoMode
from pynq.lib.video.dma import AxiVDMA


OVERLAY_PATH = (
    "/home/xilinx/jupyter_notebooks/"
    "star_anise_fpga/overlays/camera_hdmi_720p.bit"
)
CNN_OVERLAY_PATH = (
    "/home/xilinx/jupyter_notebooks/"
    "star_anise_fpga/overlays/camera_hdmi_720p_cnn_live.bit"
)
OV5640_ADDR = 0x3C


class _PollingInterrupt:
    """Compatibility object for old HWH files without PYNQ IRQ metadata."""

    async def wait(self):
        await asyncio.sleep(0.001)


def save_still(frame, filename):
    import numpy as np
    from PIL import Image

    pixels = np.asarray(frame).view(np.uint16).reshape(480, 640).copy()
    rgb = np.empty((480, 640, 3), dtype=np.uint8)
    rgb[:, :, 0] = ((pixels >> 11) & 0x1F) * 255 // 31
    rgb[:, :, 1] = ((pixels >> 5) & 0x3F) * 255 // 63
    rgb[:, :, 2] = (pixels & 0x1F) * 255 // 31
    output = Path(filename).expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgb, "RGB").save(output)
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    print(
        f"Captured still: {output} size={output.stat().st_size} "
        f"sha256={digest} raw_min/max={int(pixels.min())}/{int(pixels.max())}"
    )


# Linux mainline drivers/media/i2c/ov5640.c: ov5640_init_setting[].
# The final Linux table power-up write is intentionally performed only after
# the VDMA is running. Each tuple is (16-bit register, 8-bit value).
LINUX_INIT = [
    (0x3103, 0x11), (0x3103, 0x03), (0x3630, 0x36),
    (0x3631, 0x0E), (0x3632, 0xE2), (0x3633, 0x12),
    (0x3621, 0xE0), (0x3704, 0xA0), (0x3703, 0x5A),
    (0x3715, 0x78), (0x3717, 0x01), (0x370B, 0x60),
    (0x3705, 0x1A), (0x3905, 0x02), (0x3906, 0x10),
    (0x3901, 0x0A), (0x3731, 0x12), (0x3600, 0x08),
    (0x3601, 0x33), (0x302D, 0x60), (0x3620, 0x52),
    (0x371B, 0x20), (0x471C, 0x50), (0x3A13, 0x43),
    (0x3A18, 0x00), (0x3A19, 0xF8), (0x3635, 0x13),
    (0x3636, 0x03), (0x3634, 0x40), (0x3622, 0x01),
    (0x3C01, 0xA4), (0x3C04, 0x28), (0x3C05, 0x98),
    (0x3C06, 0x00), (0x3C07, 0x08), (0x3C08, 0x00),
    (0x3C09, 0x1C), (0x3C0A, 0x9C), (0x3C0B, 0x40),
    (0x3820, 0x41), (0x3821, 0x07), (0x3814, 0x31),
    (0x3815, 0x31), (0x3618, 0x00), (0x3612, 0x29),
    (0x3708, 0x64), (0x3709, 0x52), (0x370C, 0x03),
    (0x3A02, 0x03), (0x3A03, 0xD8), (0x3A08, 0x01),
    (0x3A09, 0x27), (0x3A0A, 0x00), (0x3A0B, 0xF6),
    (0x3A0E, 0x03), (0x3A0D, 0x04), (0x3A14, 0x03),
    (0x3A15, 0xD8), (0x4001, 0x02), (0x4004, 0x02),
    (0x3000, 0x00), (0x3002, 0x1C), (0x3004, 0xFF),
    (0x3006, 0xC3), (0x302E, 0x08),
    (0x440E, 0x00), (0x4837, 0x0A), (0x5000, 0xA7),
    (0x5001, 0xA3), (0x5180, 0xFF), (0x5181, 0xF2),
    (0x5182, 0x00), (0x5183, 0x14), (0x5184, 0x25),
    (0x5185, 0x24), (0x5186, 0x09), (0x5187, 0x09),
    (0x5188, 0x09), (0x5189, 0x88), (0x518A, 0x54),
    (0x518B, 0xEE), (0x518C, 0xB2), (0x518D, 0x50),
    (0x518E, 0x34), (0x518F, 0x6B), (0x5190, 0x46),
    (0x5191, 0xF8), (0x5192, 0x04), (0x5193, 0x70),
    (0x5194, 0xF0), (0x5195, 0xF0), (0x5196, 0x03),
    (0x5197, 0x01), (0x5198, 0x04), (0x5199, 0x6C),
    (0x519A, 0x04), (0x519B, 0x00), (0x519C, 0x09),
    (0x519D, 0x2B), (0x519E, 0x38), (0x5381, 0x1E),
    (0x5382, 0x5B), (0x5383, 0x08), (0x5384, 0x0A),
    (0x5385, 0x7E), (0x5386, 0x88), (0x5387, 0x7C),
    (0x5388, 0x6C), (0x5389, 0x10), (0x538A, 0x01),
    (0x538B, 0x98), (0x5300, 0x08), (0x5301, 0x30),
    (0x5302, 0x10), (0x5303, 0x00), (0x5304, 0x08),
    (0x5305, 0x30), (0x5306, 0x08), (0x5307, 0x16),
    (0x5309, 0x08), (0x530A, 0x30), (0x530B, 0x04),
    (0x530C, 0x06), (0x5480, 0x01), (0x5481, 0x08),
    (0x5482, 0x14), (0x5483, 0x28), (0x5484, 0x51),
    (0x5485, 0x65), (0x5486, 0x71), (0x5487, 0x7D),
    (0x5488, 0x87), (0x5489, 0x91), (0x548A, 0x9A),
    (0x548B, 0xAA), (0x548C, 0xB8), (0x548D, 0xCD),
    (0x548E, 0xDD), (0x548F, 0xEA), (0x5490, 0x1D),
    (0x5580, 0x02), (0x5583, 0x40), (0x5584, 0x10),
    (0x5589, 0x10), (0x558A, 0x00), (0x558B, 0xF8),
    (0x5800, 0x23), (0x5801, 0x14), (0x5802, 0x0F),
    (0x5803, 0x0F), (0x5804, 0x12), (0x5805, 0x26),
    (0x5806, 0x0C), (0x5807, 0x08), (0x5808, 0x05),
    (0x5809, 0x05), (0x580A, 0x08), (0x580B, 0x0D),
    (0x580C, 0x08), (0x580D, 0x03), (0x580E, 0x00),
    (0x580F, 0x00), (0x5810, 0x03), (0x5811, 0x09),
    (0x5812, 0x07), (0x5813, 0x03), (0x5814, 0x00),
    (0x5815, 0x01), (0x5816, 0x03), (0x5817, 0x08),
    (0x5818, 0x0D), (0x5819, 0x08), (0x581A, 0x05),
    (0x581B, 0x06), (0x581C, 0x08), (0x581D, 0x0E),
    (0x581E, 0x29), (0x581F, 0x17), (0x5820, 0x11),
    (0x5821, 0x11), (0x5822, 0x15), (0x5823, 0x28),
    (0x5824, 0x46), (0x5825, 0x26), (0x5826, 0x08),
    (0x5827, 0x26), (0x5828, 0x64), (0x5829, 0x26),
    (0x582A, 0x24), (0x582B, 0x22), (0x582C, 0x24),
    (0x582D, 0x24), (0x582E, 0x06), (0x582F, 0x22),
    (0x5830, 0x40), (0x5831, 0x42), (0x5832, 0x24),
    (0x5833, 0x26), (0x5834, 0x24), (0x5835, 0x22),
    (0x5836, 0x22), (0x5837, 0x26), (0x5838, 0x44),
    (0x5839, 0x24), (0x583A, 0x26), (0x583B, 0x28),
    (0x583C, 0x42), (0x583D, 0xCE), (0x5025, 0x00),
    (0x3A0F, 0x30), (0x3A10, 0x28), (0x3A1B, 0x30),
    (0x3A1E, 0x26), (0x3A11, 0x60), (0x3A1F, 0x14),
    (0x3C00, 0x04),
]

# Linux ov5640_setting_low_res[] (some values intentionally repeat init).
LINUX_LOW_RES = [
    (0x3C07, 0x08), (0x3C09, 0x1C), (0x3C0A, 0x9C),
    (0x3C0B, 0x40), (0x3814, 0x31), (0x3815, 0x31),
    (0x3618, 0x00), (0x3612, 0x29), (0x3708, 0x64),
    (0x3709, 0x52), (0x370C, 0x03), (0x3A02, 0x03),
    (0x3A03, 0xD8), (0x3A08, 0x01), (0x3A09, 0x27),
    (0x3A0A, 0x00), (0x3A0B, 0xF6), (0x3A0E, 0x03),
    (0x3A0D, 0x04), (0x3A14, 0x03), (0x3A15, 0xD8),
    (0x4001, 0x02), (0x4004, 0x02), (0x4407, 0x04),
    (0x460B, 0x35), (0x460C, 0x22), (0x3824, 0x02),
    (0x5001, 0xA3),
]

# Linux VGA DVP timing descriptor translated to the timing registers, plus
# Linux DVP power/polarity setup and RGB565 big-endian format selection.
# The clock fields correspond to an assumed 24 MHz module oscillator. Applying
# the Linux DVP clock-tree formula to these values gives a 48 MHz PCLK, which
# is the frequency constrained in camera_hdmi_720p.xdc.
VGA_RGB565 = [
    (0x3034, 0x18), (0x3035, 0x20), (0x3036, 0x60),
    (0x3037, 0x13), (0x3108, 0x01),
    (0x3800, 0x00), (0x3801, 0x00),
    (0x3802, 0x00), (0x3803, 0x04),
    (0x3804, 0x0A), (0x3805, 0x3F),
    (0x3806, 0x07), (0x3807, 0x9B),
    (0x3810, 0x00), (0x3811, 0x10),
    (0x3812, 0x00), (0x3813, 0x06),
    (0x3808, 0x02), (0x3809, 0x80),
    (0x380A, 0x01), (0x380B, 0xE0),
    (0x380C, 0x07), (0x380D, 0x68),
    (0x380E, 0x04), (0x380F, 0x38),
    (0x4730, 0x00),
    # This OV5640 DVP module was measured on the FPGA pins: bit 1 set makes
    # HREF high during horizontal blanking.  Clear it so cam_href is high for
    # exactly the 1280 byte clocks (640 RGB565 pixels) of each active line.
    # PCLK is sampled on its rising edge and VSYNC remains active high.
    (0x4740, 0x20),
    (0x300E, 0x18), (0x3017, 0x7F), (0x3018, 0xFC),
    (0x4300, 0x61), (0x501F, 0x01),
    (0x4202, 0x0F),
]

CAMERA_READBACK_REGS = (
    0x3008, 0x3034, 0x3035, 0x3036, 0x3037, 0x3108,
    0x3800, 0x3801, 0x3802, 0x3803, 0x3804, 0x3805,
    0x3806, 0x3807, 0x3808, 0x3809, 0x380A, 0x380B,
    0x380C, 0x380D, 0x380E, 0x380F, 0x3814, 0x3815,
    0x3820, 0x3821, 0x3824, 0x4202, 0x4300, 0x460B,
    0x460C, 0x4730, 0x4740, 0x501F,
)


def write_reg(iic, reg, value):
    tx = bytearray([(reg >> 8) & 0xFF, reg & 0xFF, value & 0xFF])
    tx_ptr = iic._ffi.from_buffer("unsigned char[]", tx)
    sent = iic.send(OV5640_ADDR, tx_ptr, len(tx), 0)
    iic.wait()
    if sent != len(tx):
        raise IOError(f"IIC short write at 0x{reg:04X}: {sent}/{len(tx)}")


def read_reg(iic, reg):
    tx = bytearray([(reg >> 8) & 0xFF, reg & 0xFF])
    tx_ptr = iic._ffi.from_buffer("unsigned char[]", tx)
    rx_ptr = iic._ffi.new("unsigned char[]", 1)
    sent = iic.send(OV5640_ADDR, tx_ptr, len(tx), iic.REPEAT_START)
    received = iic.receive(OV5640_ADDR, rx_ptr, 1, 0)
    iic.wait()
    if sent != len(tx) or received != 1:
        raise IOError(
            f"IIC short read at 0x{reg:04X}: tx={sent}, rx={received}"
        )
    return int(rx_ptr[0])


def load_table(iic, table):
    for reg, value in table:
        write_reg(iic, reg, value)


def camera_reset_and_check(gpio, iic):
    gpio.write(0, 0x1)
    sleep(0.020)
    gpio.write(1, 0x1)
    sleep(0.100)
    high = read_reg(iic, 0x300A)
    low = read_reg(iic, 0x300B)
    chip_id = (high << 8) | low
    print(f"0x300A = 0x{high:02X}")
    print(f"0x300B = 0x{low:02X}")
    print(f"Chip ID = 0x{chip_id:04X}")
    if chip_id != 0x5640:
        raise RuntimeError("OV5640 Chip ID mismatch; stop before enabling video")


def configure_camera_standby(iic):
    write_reg(iic, 0x3008, 0x82)  # software reset
    sleep(0.010)
    write_reg(iic, 0x3008, 0x42)  # DVP software power-down while configuring
    load_table(iic, LINUX_INIT)
    load_table(iic, LINUX_LOW_RES)
    load_table(iic, VGA_RGB565)
    sleep(0.010)


def decode_status(status0, status1):
    return {
        "pclk_seen": status0 & 0x1,
        "fifo_overflow": (status0 >> 1) & 0x1,
        "phase_error": (status0 >> 2) & 0x1,
        "lines": (status0 >> 3) & 0x3FF,
        "pixels": (status0 >> 13) & 0x7FFFF,
        "frames": status1 & 0xFFFF,
        "overflow_count": (status1 >> 16) & 0xFFFF,
    }


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def print_overlay_identity(path):
    bit_path = Path(path)
    hwh_path = bit_path.with_suffix(".hwh")
    for artifact in (bit_path, hwh_path):
        if artifact.exists():
            print(
                f"Overlay artifact: {artifact} "
                f"size={artifact.stat().st_size} "
                f"sha256={sha256_file(artifact)}"
            )
        else:
            print(f"Overlay artifact missing: {artifact}")


def reset_vdma(dma):
    # Clear a previous overlay's channel state before PYNQ allocates buffers.
    dma.mmio.write(0x00, 0x00000004)  # MM2S_DMACR.Reset
    dma.mmio.write(0x30, 0x00000004)  # S2MM_DMACR.Reset
    deadline = monotonic() + 1.0
    while monotonic() < deadline:
        if not (dma.mmio.read(0x00) & 0x4) and not (dma.mmio.read(0x30) & 0x4):
            return
        sleep(0.001)
    raise RuntimeError(
        "VDMA reset did not complete: "
        f"MM2S_DMACR=0x{dma.mmio.read(0x00):08X} "
        f"S2MM_DMACR=0x{dma.mmio.read(0x30):08X}"
    )


def decode_dmasr(value):
    names = []
    if value & 0x10:
        names.append("internal")
    if value & 0x20:
        names.append("slave")
    if value & 0x40:
        names.append("decode")
    return ",".join(names) if names else "none"


def stop_vdma_channel(channel, control_offset, status_offset, timeout=0.5):
    mmio = channel._mmio
    print(f"VDMA stop begin ctrl=0x{control_offset:02X}", flush=True)
    if hasattr(channel, "tie"):
        channel.tie(None)
    elif getattr(channel, "sourcechannel", None) is not None:
        channel.sourcechannel.tie(None)
    print(f"VDMA tie released ctrl=0x{control_offset:02X}", flush=True)
    mmio.write(control_offset, 0x00011080)
    deadline = monotonic() + timeout
    while (mmio.read(status_offset) & 0x1) == 0 and monotonic() < deadline:
        sleep(0.001)
    if (mmio.read(status_offset) & 0x1) == 0:
        print(f"VDMA channel 0x{control_offset:02X} did not halt; asserting channel reset")
        mmio.write(control_offset, 0x00011084)
        deadline = monotonic() + timeout
        while mmio.read(control_offset) & 0x4 and monotonic() < deadline:
            sleep(0.001)
        if mmio.read(control_offset) & 0x4:
            raise TimeoutError(
                f"VDMA channel reset timed out at offset 0x{control_offset:02X}"
            )
        if (mmio.read(status_offset) & 0x1) == 0:
            raise TimeoutError(
                f"VDMA channel remained active at status offset 0x{status_offset:02X}"
            )
    print(f"VDMA halted ctrl=0x{control_offset:02X}", flush=True)
    for index in range(len(channel._frames)):
        channel._frames[index] = None
    print(f"VDMA frame list cleared ctrl=0x{control_offset:02X}", flush=True)
    if hasattr(channel, "_cache"):
        channel._cache.clear()
    print(f"VDMA stop complete ctrl=0x{control_offset:02X}", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--monitor-seconds", type=float, default=600.0,
        help="diagnostic duration; default 600 s for the requested soak test",
    )
    parser.add_argument("--overlay", default=OVERLAY_PATH)
    parser.add_argument(
        "--cnn", action="store_true",
        help="load the PL CNN overlay; crop, frame queue, and inference run directly from DVP",
    )
    parser.add_argument(
        "--cnn-interval", type=float, default=2.0,
        help="seconds between CNN result/status reports",
    )
    parser.add_argument(
        "--capture-still", metavar="PNG_PATH",
        help="save one camera frame as a PNG for static HDMI display",
    )
    parser.add_argument(
        "--snapshot-and-continue", metavar="PNG_PATH",
        help="save a fresh camera frame, then continue the live HDMI preview",
    )
    parser.add_argument(
        "--capture-request-file", metavar="PATH",
        help="watch a one-line class request (bajiao/mangcao) and save a labeled frame",
    )
    parser.add_argument(
        "--capture-dir", metavar="DIR",
        help="directory for frames requested through --capture-request-file",
    )
    parser.add_argument(
        "--pixel-source-test", action="store_true",
        help="switch the diagnostic HDMI pixel mux between bars and camera",
    )
    parser.add_argument(
        "--invert-pclk", action="store_true",
        help="test the opposite OV5640 DVP PCLK polarity",
    )
    args = parser.parse_args()
    if args.cnn and args.overlay == OVERLAY_PATH:
        args.overlay = CNN_OVERLAY_PATH
    if args.cnn_interval <= 0:
        parser.error("--cnn-interval must be positive")
    if args.capture_still and args.snapshot_and_continue:
        parser.error("--capture-still and --snapshot-and-continue are exclusive")
    if (args.capture_still or args.snapshot_and_continue) and args.pixel_source_test:
        parser.error("still capture and --pixel-source-test are exclusive")
    if bool(args.capture_request_file) != bool(args.capture_dir):
        parser.error("--capture-request-file and --capture-dir must be specified together")

    print_overlay_identity(args.overlay)
    overlay = Overlay(args.overlay)
    print("IPs:", sorted(overlay.ip_dict.keys()))
    if not overlay.ip_dict["axi_vdma_0"].get("interrupts"):
        print("WARNING: VDMA interrupt metadata missing; using polling fallback")
        AxiVDMA.s2mm_introut = _PollingInterrupt()
        AxiVDMA.mm2s_introut = _PollingInterrupt()
    gpio = overlay.axi_gpio_0.channel1
    iic = overlay.axi_iic_0
    status_gpio = overlay.axi_gpio_status
    video_gpio = overlay.axi_gpio_video_status
    camera_diag_gpio = overlay.axi_gpio_camera_diag
    pixel_source = None
    if args.pixel_source_test:
        pixel_source = overlay.axi_gpio_pixel_source.channel1
        pixel_source.write(0, 1)
        print("HDMI pixel source: color bars")
    dma = overlay.axi_vdma_0
    vtc = overlay.v_tc_0
    cnn_control_gpio = overlay.axi_gpio_cnn_control.channel1 if args.cnn else None
    cnn_debug_gpio = overlay.axi_gpio_cnn_result.channel1 if args.cnn else None
    cnn_result_gpio = overlay.axi_gpio_cnn_result.channel2 if args.cnn else None
    cnn_crop_debug_gpio = overlay.axi_gpio_cnn_debug.channel1 if args.cnn else None
    cnn_queue_debug_gpio = overlay.axi_gpio_cnn_debug.channel2 if args.cnn else None

    if cnn_control_gpio is not None:
        cnn_control_gpio.write(1 << 20, 0xFFFFFFFF)
        sleep(0.010)
        cnn_control_gpio.write(1, 0xFFFFFFFF)
        print("PL_CNN ROI armed: locator-driven 244x244; waiting for detected object")

    camera_reset_and_check(gpio, iic)
    configure_camera_standby(iic)
    if args.invert_pclk:
        write_reg(iic, 0x4740, 0x00)
        print("DVP PCLK polarity test: 0x4740=0x00")
    print(
        "OV5640 register readback:",
        " ".join(
            f"{reg:04X}={read_reg(iic, reg):02X}"
            for reg in CAMERA_READBACK_REGS
        ),
    )

    # RGB565: 640 * 2 = 1280 bytes per line. PYNQ's AxiVDMA allocates and
    # programs its three frame stores when the two channels are started/tied.
    mode = VideoMode(640, 480, 16, 60)
    reset_vdma(dma)
    dma.readchannel.mode = mode       # S2MM: camera stream -> DDR
    dma.writechannel.mode = mode      # MM2S: DDR -> HDMI stream
    dma.readchannel.start()
    dma.writechannel.start()
    dma.readchannel.tie(dma.writechannel)

    # Start the camera while VTC remains disabled. This lets S2MM commit at
    # least one complete 640x480 frame before the 720p output begins.
    write_reg(iic, 0x4202, 0x00)
    write_reg(iic, 0x3008, 0x02)      # leave power-down and start DVP stream
    sleep(0.750)

    initial = decode_status(
        status_gpio.channel1.read(), status_gpio.channel2.read()
    )
    initial_mm2s = dma.mmio.read(0x04)
    initial_s2mm = dma.mmio.read(0x34)
    print("Initial DVP status:", initial)
    print(
        "Initial VDMA status: "
        f"MM2S_DMASR=0x{initial_mm2s:08X} ({decode_dmasr(initial_mm2s)}) "
        f"S2MM_DMASR=0x{initial_s2mm:08X} ({decode_dmasr(initial_s2mm)})"
    )
    # Enable VTC generator, register update, sync and all timing outputs.
    vtc.write(0x0000, 0x03FDEF07)
    sleep(0.500)

    if args.capture_still or args.snapshot_and_continue:
        stale = dma.readchannel.readframe()
        stale.freebuffer()
        still = dma.readchannel.readframe()
        save_still(still, args.capture_still or args.snapshot_and_continue)
        still.freebuffer()
        if args.capture_still:
            stop_vdma_channel(dma.readchannel, 0x30, 0x34)
            write_reg(iic, 0x3008, 0x42)
            stop_vdma_channel(dma.writechannel, 0x00, 0x04)
            print("Camera still saved; capture and DMA stopped")
            return
        print("Camera snapshot saved; live capture and HDMI continue")

    started = monotonic()
    next_cnn = started
    capture_request_file = (Path(args.capture_request_file)
                            if args.capture_request_file else None)
    capture_dir = Path(args.capture_dir) if args.capture_dir else None
    capture_count = 0
    previous_frames = None
    previous_source = 0
    previous_cnn_status = None
    try:
        while monotonic() - started < args.monitor_seconds:
            elapsed = monotonic() - started
            if capture_request_file is not None and capture_request_file.exists():
                try:
                    requested_class = capture_request_file.read_text(
                        encoding="ascii"
                    ).strip()
                except OSError as error:
                    print(f"CAPTURE_REQUEST_ERROR {error}", flush=True)
                    requested_class = ""
                try:
                    capture_request_file.unlink()
                except FileNotFoundError:
                    pass
                if requested_class not in ("bajiao", "mangcao"):
                    print("CAPTURE_REQUEST_REJECTED expected=bajiao|mangcao", flush=True)
                else:
                    assert capture_dir is not None
                    target_dir = capture_dir / requested_class
                    target_dir.mkdir(parents=True, exist_ok=True)
                    filename = (
                        f"{requested_class}_{datetime.now().strftime('%Y%m%d_%H%M%S')}_"
                        f"{capture_count:04d}.png"
                    )
                    stale = dma.readchannel.readframe()
                    stale.freebuffer()
                    frame = dma.readchannel.readframe()
                    try:
                        save_still(frame, target_dir / filename)
                    finally:
                        frame.freebuffer()
                    capture_count += 1
                    print(f"LABELED_FRAME_SAVED class={requested_class} "
                          f"path={target_dir / filename}", flush=True)
            if pixel_source is not None:
                source = (int(elapsed // 10) % 2)
                if source != previous_source:
                    pixel_source.write(source, 1)
                    print(f"HDMI pixel source: {'camera' if source else 'color bars'} at {elapsed:.1f}s")
                    previous_source = source
            raw0 = status_gpio.channel1.read()
            raw1 = status_gpio.channel2.read()
            s = decode_status(raw0, raw1)
            mm2s_dmasr = dma.mmio.read(0x04)
            s2mm_dmasr = dma.mmio.read(0x34)
            video_status = video_gpio.channel1.read()
            video_flags = video_gpio.channel2.read()
            diag0 = camera_diag_gpio.channel1.read()
            pclk_cycles = camera_diag_gpio.channel2.read()
            line_max = diag0 & 0x7FF
            line_min = (diag0 >> 11) & 0x7FF
            odd_lines = (diag0 >> 22) & 0x3FF
            clk_locked = video_flags & 0x1
            video_locked = (video_flags >> 1) & 0x1
            underflow = (video_flags >> 2) & 0x1
            video_overflow = (video_flags >> 3) & 0x1
            print(
                f"t={monotonic()-started:7.1f}s "
                f"pclk={s['pclk_seen']} frames={s['frames']} "
                f"lines={s['lines']} pixels={s['pixels']} "
                f"overflow={s['fifo_overflow']}/{s['overflow_count']} "
                f"phase_error={s['phase_error']} "
                f"line_min/max={line_min}/{line_max} odd_lines={odd_lines} "
                f"pclk_cycles/frame={pclk_cycles} "
                f"clk_locked={clk_locked} video_locked={video_locked} "
                f"vid_underflow={underflow} vid_overflow={video_overflow} "
                f"vid_status=0x{video_status:08X} "
                f"MM2S_DMASR=0x{mm2s_dmasr:08X} "
                f"S2MM_DMASR=0x{s2mm_dmasr:08X} "
                f"DMA_errors={decode_dmasr(mm2s_dmasr)}/{decode_dmasr(s2mm_dmasr)}"
            )
            if not args.capture_still and previous_frames == s["frames"]:
                print("WARNING: completed-frame counter did not advance")
            previous_frames = s["frames"]
            if s["lines"] not in (0, 480) or s["pixels"] not in (0, 307200):
                print("ERROR: DVP frame must be exactly 480 lines / 307200 pixels")
            if s["phase_error"] or s["fifo_overflow"]:
                print("ERROR: DVP phase/FIFO diagnostic is asserted")
            if not clk_locked or not video_locked or underflow or video_overflow:
                print("ERROR: HDMI clock/video lock diagnostic is not clean")
            if (mm2s_dmasr | s2mm_dmasr) & 0x70:
                print("ERROR: VDMA DMASR contains an internal/slave/decode error")
            if args.cnn and monotonic() >= next_cnn:
                result = cnn_result_gpio.read()
                debug = cnn_debug_gpio.read()
                crop_debug = cnn_crop_debug_gpio.read()
                queue_debug = cnn_queue_debug_gpio.read()
                recognized = result & 1
                class_id = (result >> 1) & 0x3
                label = {0: "bajiao", 1: "mangcao"}.get(class_id, "unknown")
                cnn_status = (result, debug, crop_debug, queue_debug)
                if cnn_status != previous_cnn_status:
                    print(
                        f"PL_CNN source=DVP result={'recognized' if recognized else 'pending'} "
                        f"class={label} result_gpio=0x{result:X} "
                        f"crop_frames={((debug >> 2) & 0x3F)} "
                        f"crop_pixels={debug >> 16} predictions={(debug >> 8) & 0xFF} "
                        f"agree={debug & 0x3} "
                        f"crop_en={(crop_debug >> 31) & 1} "
                        f"crop_sof={(crop_debug >> 30) & 1} "
                        f"crop_error={(crop_debug >> 29) & 1} "
                        f"crop_max_x={((crop_debug >> 19) & 0x3FF)} "
                        f"crop_max_y={((crop_debug >> 10) & 0x1FF)} "
                        f"crop_out={(crop_debug & 0x3FF)} "
                        f"roi_frames={queue_debug >> 16} roi_dropped={queue_debug & 0xFFFF}"
                    )
                    previous_cnn_status = cnn_status
                next_cnn = monotonic() + args.cnn_interval
            sleep(1.0)
    finally:
        # Stop S2MM while frames are still arriving so it can finish a frame.
        try:
            stop_vdma_channel(dma.readchannel, 0x30, 0x34)
        finally:
            stop_vdma_channel(dma.writechannel, 0x00, 0x04)


if __name__ == "__main__":
    main()
