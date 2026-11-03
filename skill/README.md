# Reusable workflow: debug a fixed-camera FPGA shape detector

## When to use

Use this workflow for a fixed camera, single specimen, light background and a
PYNQ-Z1/OV5640 video chain. It helps separate camera-link faults, lighting
changes, segmentation errors and tip-detection errors before changing the
classifier. It is a debugging method, not a validated botanical safety test.

## Inputs and outputs

- Input: a 640x480 RGB565 frame, camera status counters, one known specimen,
  and a captured image or six-panel HDMI recording.
- Output: the first failing stage, its measured evidence, and a repeatable
  counterexample for the next iteration.

## Procedure

1. Verify camera transport first: expect 480 lines, 307200 pixels, 640 pixels
   per line, and no increasing FIFO overflow count. Do not tune image thresholds
   while the frame itself is incomplete.
2. Fix camera position and illumination. Record the specimen identity and
   lighting condition. Use physically distinct specimens when evaluating
   classification; repeated photos of one specimen are correlated.
3. Inspect the displayed stages in order: original image, lighting-corrected
   image, foreground mask, repaired silhouette, candidate tips, stable tips.
   Mark the earliest stage that loses a real tip or creates a false one.
4. For a segmentation failure, compare brightness and chromatic masks and
   retain a before/after image. For a contour failure, inspect hole filling,
   connected regions and the radial profile. For a peak failure, check peak
   prominence, angular spacing and history matching. Change one parameter or
   operation at a time and repeat the same specimen and lighting setup.
5. Verify the board result on a new physical specimen and a changed lighting
   condition. Report per-specimen outcomes and abstentions, not only frame-level
   accuracy. Keep the failed examples in the validation record.

## Concrete example from this project

A live specimen had a visible tip between the displayed labels 5 and 6 but the
detector omitted it. The useful response was to trace that tip through the
silhouette and radial peak views, then adjust the candidate peak logic and
check the same physical specimen again. A single corrected screenshot would
not establish general accuracy, so the project report leaves cross-specimen
accuracy unclaimed.

## Implementation anchors

- HLS algorithm: `camera_hdmi_720p_fpga_sixpanel/hls/sixpanel_accel.cpp`
- RTL result logic: `camera_hdmi_720p_fpga_sixpanel/rtl/`
- Board controller: `board/overlays/fpga_sixpanel_support/`
- Measured implementation: `reports_and_build_delivery/`
- Full design and limits: `report/design_report.pdf`

## Boundaries

The delivered design samples a 160x120 working image, updates at about 2.6
times per second in the recorded board run, and uses a provisional tip-count
threshold. Strong shadows, occlusion, damaged specimens, changed backgrounds
and new specimens require fresh validation. This workflow does not determine
whether a medicinal material is safe to ingest.
