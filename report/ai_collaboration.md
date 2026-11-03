# AI collaboration and human verification record

This is a concise, non-verbatim record of project discussions. The quoted
Chinese requests are user prompts from the project conversation; the response
column summarizes the engineering direction rather than pretending to be an
exact transcript. Design evidence is in source, reports, tests and board
recordings. AI suggestions are not performance measurements.

| User prompt or correction | Engineering response and correction | Evidence / remaining limit |
| --- | --- | --- |
| “不不不我想实现的事消除影子对cnn卷积的影响” | Examined lighting compensation and segmentation before classification. The project later changed to an interpretable silhouette and tip-count route. | HLS implements lighting correction and two segmentation branches; cross-lighting accuracy is unmeasured. |
| “不要使用给定角数跟方向，让算法自己识别” | Rejected a fixed list of tip directions; used a radial contour profile, candidate peaks and history matching. | `sixpanel_accel.cpp` contains the implemented image path; new-specimen validation remains limited. |
| “对于现在这个物体，5和6之间有个角不识别” | Treated the missing tip as a concrete counterexample. Inspected the silhouette and peak views before revising detection. | Six-panel display allows stage-by-stage inspection; one example cannot establish general accuracy. |
| “我希望将所有的算法部署在fpga上，而不是用python你觉得怎么样” | Moved per-pixel image processing into a PL-side HLS accelerator. Kept Python for camera/VDMA/DDR setup and scheduling. | HLS source, RTL, bitstream and board controller show the division. |

Human checks included inspection of live images, rejection of incorrectly
marked tips, and confirmation of the final experiment scope. The delivered
classifier uses a provisional threshold: fewer than 10 detected tips maps to
“八角”, 10 or more to “莽草”, and invalid targets to “未识别”. The limited
number of independent specimens does not support a food or medicine safety
claim.

See `skill/README.md` for the reusable debugging workflow and
`report/design_report.pdf` for the design report and measured constraints.
