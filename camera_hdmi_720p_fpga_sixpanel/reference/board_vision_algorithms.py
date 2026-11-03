#!/usr/bin/env python3
"""Selected PYNQ-side vision panels using NumPy, Pillow and system OpenCV.

The FPGA remains responsible for camera capture and its foreground mask. This
module runs the selected temporal, illumination, edge, extraction and tip
tracking stages on the Zynq ARM, so the laptop only displays the resulting
JPEG panels.
"""

from __future__ import annotations

from collections import deque
from time import perf_counter
import sys

# PYNQ's isolated venv does not add Debian's ARM OpenCV package automatically.
sys.path.append("/usr/lib/python3/dist-packages")
import cv2
import numpy as np
from PIL import Image, ImageDraw


SENSOR_WIDTH, SENSOR_HEIGHT = 640, 480
WIDTH, HEIGHT = 320, 240
PROCESS_W, PROCESS_H = 160, 120
PANEL_W, PANEL_H, HEADER_H = 320, 240, 32
CELL_H = PANEL_H + HEADER_H
PANEL_NAMES = (
    "1 ORIGINAL CAMERA",
    "4 CANNY EDGES / ORIGINAL",
    "6 CHROMA SHADOW SUPPRESSION",
    "7 DENOISE + WHITE BACKGROUND",
    "8 RADIAL ANGLE CANDIDATES",
    "11 FPGA MASK + TIP CONSENSUS",
)


def rgb565_to_rgb(pixels: np.ndarray) -> np.ndarray:
    r = (((pixels >> 11) & 0x1F) * 255 // 31).astype(np.uint8)
    g = (((pixels >> 5) & 0x3F) * 255 // 63).astype(np.uint8)
    b = ((pixels & 0x1F) * 255 // 31).astype(np.uint8)
    return np.dstack((r, g, b))


def _display(image: np.ndarray) -> np.ndarray:
    return cv2.resize(image.astype(np.uint8), (PANEL_W, PANEL_H),
                      interpolation=cv2.INTER_AREA)


def _fill_light(rgb: np.ndarray) -> np.ndarray:
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV)
    hue, saturation, value = cv2.split(hsv)
    value_float = value.astype(np.float32)
    sigma = max(1.0, rgb.shape[1] / 20.0)
    illumination = cv2.GaussianBlur(value_float, (0, 0), sigmaX=sigma)
    reference = float(np.median(illumination))
    gain = np.clip(reference / np.maximum(illumination, 24.0), 0.60, 2.20)
    corrected = np.clip(value_float * gain, 0, 255).astype(np.uint8)
    return cv2.cvtColor(cv2.merge((hue, saturation, corrected)), cv2.COLOR_HSV2RGB)


def _normalize_chroma(rgb: np.ndarray) -> np.ndarray:
    source = rgb.astype(np.uint16)
    maximum = source.max(axis=2, keepdims=True)
    scaled = source * 255 // np.maximum(maximum, 1)
    return np.where(maximum != 0, scaled, 0).astype(np.uint8)


def _canny(rgb: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
    gray = cv2.GaussianBlur(gray, (3, 3), 0)
    # Half-resolution input; thresholds are scaled from the original Canny view.
    scale = rgb.shape[1] / float(WIDTH)
    edge_map = cv2.Canny(gray, max(8, int(28 * scale)), max(16, int(65 * scale)))
    output = np.full((*edge_map.shape, 3), 28, dtype=np.uint8)
    output[edge_map > 0] = (40, 220, 255)
    return output


def _bilateral3(rgb: np.ndarray) -> np.ndarray:
    return cv2.bilateralFilter(rgb, d=5, sigmaColor=28, sigmaSpace=4)


def _morph(mask: np.ndarray, kind: str, size: int) -> np.ndarray:
    operation = cv2.dilate if kind == "dilate" else cv2.erode
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (size, size))
    return operation(mask.astype(np.uint8), kernel) > 0


def _largest_component(mask: np.ndarray) -> tuple[np.ndarray, tuple[int, int, int, int] | None]:
    count, labels, stats, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8), 8)
    if count <= 1:
        return np.zeros_like(mask), None
    selected = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    area = int(stats[selected, cv2.CC_STAT_AREA])
    minimum_area = max(30, int(125 * mask.shape[0] * mask.shape[1] / (HEIGHT * WIDTH)))
    if area < minimum_area:
        return np.zeros_like(mask), None
    x, y, w, h, _ = (int(value) for value in stats[selected])
    return labels == selected, (x, y, x+w, y+h)


def _extract_white(source: np.ndarray) -> tuple[np.ndarray, np.ndarray, tuple[float, float] | None]:
    height, width = source.shape[:2]
    denoised = _bilateral3(source)
    hsv = cv2.cvtColor(denoised, cv2.COLOR_RGB2HSV)
    hue, saturation, _ = cv2.split(hsv)
    edge = max(8, width // 8)
    margins = np.concatenate((hue[:, :edge], hue[:, width-edge:]), axis=1)
    baseline = np.median(margins, axis=1).astype(np.uint8)
    kernel = max(3, min(41, (height // 12) | 1))
    baseline = cv2.medianBlur(baseline.reshape(height, 1), kernel).reshape(height)
    delta = np.abs(hue.astype(np.int16) - baseline[:, None].astype(np.int16))
    delta = np.minimum(delta, 180 - delta)
    foreground = (delta >= 12) & (saturation >= 40)
    margin = max(3, min(16, min(width, height) // 30))
    foreground[:margin] = False
    foreground[-margin:] = False
    foreground[:, :margin] = False
    foreground[:, -margin:] = False
    foreground = _morph(_morph(foreground, "erode", 3), "dilate", 3)
    foreground = _morph(_morph(foreground, "dilate", 5), "erode", 5)
    component, box = _largest_component(foreground)
    panel = np.full((PANEL_H, PANEL_W, 3), 255, dtype=np.uint8)
    if box is None:
        return panel, component, None
    x0, y0, x1, y1 = box
    pad = 12
    x0, y0 = max(0, x0-pad), max(0, y0-pad)
    x1, y1 = min(width, x1+pad), min(height, y1+pad)
    crop = denoised[y0:y1, x0:x1]
    alpha = component[y0:y1, x0:x1].astype(np.uint8) * 255
    alpha = cv2.morphologyEx(alpha, cv2.MORPH_CLOSE,
                             cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3)))
    target_w, target_h = PANEL_W - 40, PANEL_H - 40
    scale = min(target_w / max(1, crop.shape[1]), target_h / max(1, crop.shape[0]))
    out_w = max(1, int(round(crop.shape[1] * scale)))
    out_h = max(1, int(round(crop.shape[0] * scale)))
    crop = cv2.resize(crop, (out_w, out_h), interpolation=cv2.INTER_CUBIC)
    alpha = cv2.resize(alpha, (out_w, out_h), interpolation=cv2.INTER_LINEAR)
    alpha_float = alpha.astype(np.float32)[:, :, None] / 255.0
    white = np.full_like(crop, 255)
    isolated = np.clip(crop.astype(np.float32) * alpha_float
                       + white.astype(np.float32) * (1.0-alpha_float), 0, 255).astype(np.uint8)
    px, py = (PANEL_W-out_w)//2, (PANEL_H-out_h)//2
    panel[py:py+out_h, px:px+out_w] = isolated
    ys, xs = np.nonzero(component)
    center = (float(xs.mean()), float(ys.mean())) if xs.size else None
    return panel, component, center


def _radial_profile(mask: np.ndarray, center: tuple[float, float], bins: int = 360) -> np.ndarray:
    eroded = _morph(mask, "erode", 3)
    boundary = mask & ~eroded
    ys, xs = np.nonzero(boundary)
    if xs.size < 10:
        ys, xs = np.nonzero(mask)
    if xs.size < 10:
        return np.zeros(bins, dtype=np.float32)
    cx, cy = center
    dx, dy = xs.astype(np.float32) - cx, cy - ys.astype(np.float32)
    angles = np.mod(np.degrees(np.arctan2(dy, dx)), 360.0)
    indices = np.floor(angles * bins / 360.0).astype(np.int32) % bins
    radii = np.hypot(dx, dy)
    profile = np.full(bins, np.nan, dtype=np.float32)
    np.maximum.at(profile, indices, radii)
    valid = np.flatnonzero(np.isfinite(profile))
    if valid.size < bins // 2:
        return np.zeros(bins, dtype=np.float32)
    return np.interp(np.arange(bins),
                     np.concatenate((valid-bins, valid, valid+bins)),
                     np.tile(profile[valid], 3)).astype(np.float32)


def _smooth_circular(values: np.ndarray, radius: int) -> np.ndarray:
    offsets = np.arange(-radius, radius + 1)
    weights = np.exp(-0.5 * (offsets / max(1.0, radius / 2.0)) ** 2)
    weights /= weights.sum()
    padded = np.concatenate((values[-radius:], values, values[:radius]))
    return np.convolve(padded, weights, mode="valid").astype(np.float32)


def _find_peaks(profile: np.ndarray, minimum_degrees: int = 18) -> list[tuple[int, float]]:
    bins = profile.size
    radius = max(2, minimum_degrees // 2)
    scale = float(np.percentile(profile, 95) - np.percentile(profile, 10))
    prominence_min = max(0.35, scale * 0.005)
    # Do the circular neighborhood scans in vectorized NumPy operations. A
    # Python loop over all 360 bins is disproportionately expensive on ARM.
    neighborhood_max = np.maximum.reduce([np.roll(profile, offset)
                                          for offset in range(-radius, radius + 1)])
    neighborhood_min = np.minimum.reduce([np.roll(profile, -offset)
                                          for offset in range(1, radius + 1)])
    opposite_min = np.minimum.reduce([np.roll(profile, offset)
                                      for offset in range(1, radius + 1)])
    is_peak = (profile >= neighborhood_max) & (profile > np.roll(profile, 1))
    prominence = profile - np.maximum(neighborhood_min, opposite_min)
    candidates = [(int(i), float(prominence[i]))
                  for i in np.flatnonzero(is_peak & (prominence >= prominence_min))]
    min_bins = int(round(minimum_degrees * bins / 360.0))
    selected: list[tuple[int, float]] = []
    for candidate in sorted(candidates, key=lambda item: (float(profile[item[0]]), item[1]), reverse=True):
        if all(min((candidate[0]-old[0]) % bins, (old[0]-candidate[0]) % bins) >= min_bins
               for old in selected):
            selected.append(candidate)
    return sorted(selected)


def _angle_panel(extracted: np.ndarray, mask: np.ndarray,
                 center: tuple[float, float] | None) -> tuple[np.ndarray, np.ndarray]:
    panel = extracted.copy()
    if center is None or not np.any(mask):
        return panel, np.empty((0, 2), dtype=np.float32)
    profile = _radial_profile(mask, center)
    peaks = _find_peaks(_smooth_circular(profile, radius=6))
    points = []
    image = Image.fromarray(panel, "RGB")
    draw = ImageDraw.Draw(image)
    cx, cy = center
    scale_x = PANEL_W / float(mask.shape[1])
    scale_y = PANEL_H / float(mask.shape[0])
    for order, (angle_bin, _prominence) in enumerate(peaks, start=1):
        angle = angle_bin * 2.0 * np.pi / profile.size
        radius = float(profile[angle_bin])
        x, y = cx + radius*np.cos(angle), cy - radius*np.sin(angle)
        points.append((x, y))
        px, py = int(round(x * scale_x)), int(round(y * scale_y))
        pcx, pcy = int(round(cx * scale_x)), int(round(cy * scale_y))
        draw.line((pcx, pcy, px, py), fill=(35, 190, 35), width=2)
        draw.ellipse((px-4, py-4, px+4, py+4), fill=(225, 20, 20))
        draw.text((px+5, py-7), str(order), fill=(120, 0, 0))
    pcx, pcy = int(round(cx * scale_x)), int(round(cy * scale_y))
    draw.ellipse((pcx-4, pcy-4, pcx+4, pcy+4), fill=(20, 80, 220))
    draw.text((8, 8), "ANGLE CANDIDATES: %d" % len(peaks), fill=(20, 20, 20))
    return np.asarray(image), np.asarray(points, dtype=np.float32).reshape(-1, 2)


class BoardVisionPipeline:
    """Build the selected six panels on the PYNQ ARM."""

    def __init__(self) -> None:
        self.fill_history: deque[np.ndarray] = deque(maxlen=5)
        self.tip_history: deque[np.ndarray] = deque(maxlen=9)
        self.last_timings: dict[str, float] = {}
        self.last_stable_tip_count = 0

    @staticmethod
    def classify_tip_count(count: int) -> int | None:
        """Return the prototype's non-CNN class from stable radial tips.

        This is an initial shape-count rule for the live demo, not a validated
        botanical classifier. The labeled sample sets overlap in tip count.
        """
        if 7 <= count <= 9:
            return 0  # 八角-like count
        if 10 <= count <= 14:
            return 1  # 莽草-like count
        return None

    def _stable_tips(self, points: np.ndarray, center: tuple[float, float],
                     scale: float) -> np.ndarray:
        vectors = (points - np.asarray(center, dtype=np.float32)) / max(scale, 1.0)
        self.tip_history.append(vectors)
        clusters: list[dict[str, object]] = []
        for frame_index, frame_vectors in enumerate(self.tip_history):
            for vector in frame_vectors:
                matches = []
                for cluster_index, cluster in enumerate(clusters):
                    if frame_index in cluster["frames"]:
                        continue
                    prototype = np.median(np.stack(cluster["vectors"]), axis=0)
                    distance = float(np.linalg.norm(vector-prototype))
                    if distance <= 0.18:
                        matches.append((distance, cluster_index))
                if matches:
                    _, chosen = min(matches)
                    clusters[chosen]["vectors"].append(vector)
                    clusters[chosen]["frames"].add(frame_index)
                else:
                    clusters.append({"vectors": [vector], "frames": {frame_index}})
        required = max(2, int(np.ceil(len(self.tip_history) * 0.55)))
        stable = [np.median(np.stack(item["vectors"]), axis=0)
                  for item in clusters if len(item["frames"]) >= required]
        if not stable:
            return np.empty((0, 2), dtype=np.float32)
        result = np.asarray(center, dtype=np.float32) + scale * np.asarray(stable, dtype=np.float32)
        angles = np.mod(np.arctan2(center[1]-result[:, 1], result[:, 0]-center[0]), 2*np.pi)
        return result[np.argsort(angles)]

    def _tip_panel(self, mask: np.ndarray) -> np.ndarray:
        panel = np.full((HEIGHT, WIDTH, 3), 255, dtype=np.uint8)
        panel[mask] = 0
        ys, xs = np.nonzero(mask)
        if xs.size < 10:
            self.tip_history.append(np.empty((0, 2), dtype=np.float32))
            self.last_stable_tip_count = 0
            return _display(panel)
        center = (float(xs.mean()), float(ys.mean()))
        profile = _radial_profile(mask, center)
        peaks = _find_peaks(_smooth_circular(profile, radius=6))
        points = []
        for angle_bin, _ in peaks:
            angle = angle_bin * 2.0 * np.pi / profile.size
            radius = float(profile[angle_bin])
            points.append((center[0]+radius*np.cos(angle), center[1]-radius*np.sin(angle)))
        scale = max(1.0, float(np.percentile(profile, 95)))
        stable = self._stable_tips(np.asarray(points, dtype=np.float32).reshape(-1, 2), center, scale)
        self.last_stable_tip_count = int(len(stable))
        image = Image.fromarray(panel, "RGB")
        draw = ImageDraw.Draw(image)
        for index, point in enumerate(stable, start=1):
            x, y = int(round(float(point[0]))), int(round(float(point[1])))
            draw.line((int(center[0]), int(center[1]), x, y), fill=(40, 180, 40), width=2)
            draw.ellipse((x-4, y-4, x+4, y+4), fill=(225, 20, 20))
            draw.text((x+5, y-7), str(index), fill=(120, 0, 0))
        draw.ellipse((int(center[0])-4, int(center[1])-4,
                      int(center[0])+4, int(center[1])+4), fill=(0, 190, 255))
        draw.text((8, 8), "TIP CONSENSUS: %d" % len(stable), fill=(20, 20, 20))
        return _display(np.asarray(image))

    def render(self, pixels: np.ndarray, quality: int = 78) -> bytes:
        if pixels.shape != (SENSOR_HEIGHT, SENSOR_WIDTH * 2):
            raise ValueError("expected FPGA raw+mask frame with shape 480x1280")
        started = perf_counter()
        # Sample RGB565 directly at half resolution before expanding channels.
        raw = rgb565_to_rgb(pixels[::2, :SENSOR_WIDTH:2])
        mask_pixels = pixels[::2, SENSOR_WIDTH::2]
        fpga_mask = mask_pixels < 0x8000
        raw_small = cv2.resize(raw, (PROCESS_W, PROCESS_H),
                               interpolation=cv2.INTER_AREA)
        t_prepare = perf_counter()

        t0 = perf_counter()
        fill_small = _fill_light(raw_small)
        self.fill_history.append(fill_small)
        stable_fill_small = np.median(np.stack(self.fill_history), axis=0).astype(np.uint8)
        stable_fill = cv2.resize(stable_fill_small, (WIDTH, HEIGHT),
                                 interpolation=cv2.INTER_LINEAR)
        t_fill = perf_counter()

        shadow_small = _normalize_chroma(stable_fill_small)
        shadow = cv2.resize(shadow_small, (WIDTH, HEIGHT),
                            interpolation=cv2.INTER_LINEAR)
        t_chroma = perf_counter()

        edges = _canny(raw_small)
        t_canny = perf_counter()

        extracted, specimen_mask, center = _extract_white(shadow_small)
        t_extract = perf_counter()

        angles, _angle_points = _angle_panel(extracted, specimen_mask, center)
        t_angles = perf_counter()

        tips = self._tip_panel(fpga_mask)
        t_tips = perf_counter()

        panels = [stable_fill, edges, shadow, extracted, angles, tips]
        canvas = np.full((CELL_H * 2, PANEL_W * 3, 3), (23, 23, 23), dtype=np.uint8)
        for index, (panel, label) in enumerate(zip(panels, PANEL_NAMES)):
            row, col = divmod(index, 3)
            x, y = col * PANEL_W, row * CELL_H
            cv2.rectangle(canvas, (x, y), (x+PANEL_W-1, y+HEADER_H-1), (32, 32, 32), -1)
            cv2.putText(canvas, label, (x+8, y+25), cv2.FONT_HERSHEY_SIMPLEX,
                        0.48, (245, 245, 245), 1, cv2.LINE_AA)
            displayed = _display(panel)
            canvas[y+HEADER_H:y+CELL_H, x:x+PANEL_W] = displayed[:, :, ::-1]
        ok, encoded = cv2.imencode(".jpg", canvas,
                                   [cv2.IMWRITE_JPEG_QUALITY, int(quality)])
        if not ok:
            raise RuntimeError("OpenCV JPEG encoding failed")
        finished = perf_counter()
        self.last_timings = {
            "prepare_ms": round((t_prepare-started) * 1000, 1),
            "fill_ms": round((t_fill-t0) * 1000, 1),
            "chroma_ms": round((t_chroma-t_fill) * 1000, 1),
            "canny_ms": round((t_canny-t_chroma) * 1000, 1),
            "extract_ms": round((t_extract-t_canny) * 1000, 1),
            "angles_ms": round((t_angles-t_extract) * 1000, 1),
            "consensus_ms": round((t_tips-t_angles) * 1000, 1),
            "compose_ms": round((finished-t_tips) * 1000, 1),
            "total_ms": round((finished-started) * 1000, 1),
        }
        return encoded.tobytes()

    def render_hdmi_mosaic(self, pixels: np.ndarray) -> np.ndarray:
        """Build a 1280x640 RGB565 six-panel mosaic for the HDMI VDMA path.

        ``pixels`` is one raw 640x480 RGB565 frame from the camera S2MM buffer.
        All six views and the tip count are computed in PYNQ ARM software; no
        FPGA image-processing or CNN stream feeds this function.
        """
        if pixels.shape != (SENSOR_HEIGHT, SENSOR_WIDTH):
            raise ValueError("expected one raw 640x480 RGB565 frame")
        started = perf_counter()

        raw_full = rgb565_to_rgb(pixels)
        raw_panel = cv2.resize(raw_full, (WIDTH, HEIGHT),
                               interpolation=cv2.INTER_AREA)
        raw_small = cv2.resize(rgb565_to_rgb(pixels[::2, ::2]), (PROCESS_W, PROCESS_H),
                               interpolation=cv2.INTER_AREA)
        fill_small = _fill_light(raw_small)
        self.fill_history.append(fill_small)
        stable_fill_small = np.median(np.stack(self.fill_history), axis=0).astype(np.uint8)
        stable_fill = cv2.resize(stable_fill_small, (WIDTH, HEIGHT),
                                 interpolation=cv2.INTER_LINEAR)
        shadow_small = _normalize_chroma(stable_fill_small)
        shadow = cv2.resize(shadow_small, (WIDTH, HEIGHT),
                            interpolation=cv2.INTER_LINEAR)
        edges = _display(_canny(raw_small))
        _extracted_crop, specimen_mask, center = _extract_white(shadow_small)
        _angles_crop, angle_points = _angle_panel(_extracted_crop, specimen_mask, center)
        mask_full = cv2.resize(specimen_mask.astype(np.uint8), (WIDTH, HEIGHT),
                               interpolation=cv2.INTER_NEAREST).astype(bool)
        extracted_full = np.full_like(shadow, 255)
        extracted_full[mask_full] = shadow[mask_full]
        angles_full = shadow.copy()
        if center is not None:
            image = Image.fromarray(angles_full, "RGB")
            draw = ImageDraw.Draw(image)
            scale_x = WIDTH / float(specimen_mask.shape[1])
            scale_y = HEIGHT / float(specimen_mask.shape[0])
            cx, cy = center
            pcx, pcy = int(round(cx * scale_x)), int(round(cy * scale_y))
            for order, (point_x, point_y) in enumerate(angle_points, start=1):
                px = int(round(float(point_x) * scale_x))
                py = int(round(float(point_y) * scale_y))
                draw.line((pcx, pcy, px, py), fill=(35, 190, 35), width=2)
                draw.ellipse((px-4, py-4, px+4, py+4), fill=(225, 20, 20))
                draw.text((px+5, py-7), str(order), fill=(120, 0, 0))
            draw.ellipse((pcx-4, pcy-4, pcx+4, pcy+4), fill=(20, 80, 220))
            draw.text((8, 8), "ANGLE CANDIDATES: %d" % len(angle_points),
                      fill=(20, 20, 20))
            angles_full = np.asarray(image)
        tips = self._tip_panel(specimen_mask)

        panels = [raw_panel, edges, shadow, extracted_full, angles_full, tips]
        labels = (
            "1 ORIGINAL CAMERA",
            "4 CANNY EDGES",
            "6 CHROMA SHADOW SUPPRESSION",
            "7 DENOISE + WHITE SEGMENT",
            "8 RADIAL ANGLE CANDIDATES",
            "11 FOREGROUND + TIP CONSENSUS",
        )
        canvas = np.zeros((640, 1280, 3), dtype=np.uint8)
        column_edges = (0, 426, 853, 1280)
        for index, (panel, label) in enumerate(zip(panels, labels)):
            row, col = divmod(index, 3)
            left, right = column_edges[col], column_edges[col + 1]
            y = row * 320
            displayed = cv2.resize(panel, (right - left, 320),
                                   interpolation=cv2.INTER_LINEAR)
            canvas[y:y + 320, left:right] = displayed
            cv2.rectangle(canvas, (left, y), (right - 1, y + 27), (24, 24, 24), -1)
            cv2.putText(canvas, label, (left + 8, y + 20),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.50, (245, 245, 245), 1,
                        cv2.LINE_AA)

        rgb = canvas.astype(np.uint16)
        packed = (((rgb[:, :, 0] >> 3) << 11)
                  | ((rgb[:, :, 1] >> 2) << 5)
                  | (rgb[:, :, 2] >> 3))
        finished = perf_counter()
        self.last_timings = {
            "mosaic_total_ms": round((finished - started) * 1000, 1),
        }
        return packed
