# 星形果实识别系统：build22 提交代码

这是 2026 年 10 月 28 日已上板的 PYNQ-Z1 六画面版本。器件为 `xc7z020clg400-1`，摄像头为 OV5640，输出为 720p HDMI。**本版不运行 CNN，也不依赖训练权重。**

## 工作流程

`OV5640 640×480 RGB565 → PL 采集和 VDMA → HLS 六画面图像处理 → 稳定尖角数 → RTL 分类及按键锁存 → HDMI`。

- `sixpanel_accel.cpp`：光照补偿、分割、轮廓及尖端检测，生成六画面拼图和稳定尖角数。
- `vision_tip_count_classifier.v`：有效目标下，尖角数小于 10 判为八角，10 及以上判为莽草；无效目标为未识别。
- `vision_result_button_latch.v`：BTN0 锁存/清除显示结果。
- 板端 Python：配置摄像头和硬件，管理 DDR 帧缓冲、VDMA 与 HLS 调用；不逐像素执行上述视觉算法。

## 目录

| 路径 | 用途 |
| --- | --- |
| `board/overlays/` | 已生成的 `.bit`、`.hwh` 和板端启动程序 |
| `camera_hdmi_720p/src/` | 采集、时钟、状态及按键 RTL |
| `camera_hdmi_720p/constraints/` | 摄像头、HDMI、按键引脚约束 |
| `camera_hdmi_720p/board_files/` | PYNQ-Z1 板卡定义 |
| `camera_hdmi_720p_fpga_sixpanel/hls/` | 图像处理 HLS 源码与配置 |
| `camera_hdmi_720p_fpga_sixpanel/rtl/` | 角数分类与结果锁存 RTL |
| `camera_hdmi_720p_fpga_sixpanel/reference/` | 算法 Python 参考实现；不是上板实时主算法 |
| `camera_hdmi_720p_python_sixpanel_delivery/` | 实际使用的六画面 HDMI 显示 RTL |
| `camera_hdmi_720p_fpga_sixpanel*/ip_repo/` | 打包的 HLS IP 与 HDMI IP，供 Vivado 重建 |
| `docs/original_delivery_notes.md` | 原交付说明，文件名已按竞赛要求改为英文 |
| `build/` | Vivado 重建脚本 |
| `verification/` | 按键与分类边界的仿真 testbench |
| `reports_and_build_delivery/` | build22 实现与时序报告 |
| `report/design_report.pdf` | 竞赛设计报告；`report/latex/` 为可编辑 LaTeX 源码与配图 |
| `report/ai_collaboration.md` | 需求、模型建议、人工纠错和证据边界摘要 |
| `skill/README.md` | 可复用的固定机位形态检测调试流程 |
| `LICENSE`, `THIRD_PARTY_NOTICES.md` | 原创源码许可和第三方文件的权利边界 |

## 上板运行

将 `board/overlays/` 的内容复制到板端 `/home/xilinx/jupyter_notebooks/star_anise_fpga/overlays/`，再运行：

```bash
sudo bash /home/xilinx/jupyter_notebooks/star_anise_fpga/overlays/fpga_sixpanel_support/start_board_fpga_sixpanel.sh
```

BTN0 按一次显示并锁存分类，再按一次返回 WAIT。

## 重建与核验

在 **不含中文的短路径**解压，安装 Vivado 2026.1 并确保 `vivado.bat` 可在 PATH 找到，然后执行 `build/rebuild.ps1`。该脚本使用随包提供的 HLS IP，不需要先重新综合 HLS。`build/build.tcl` 同时包含其他历史模式分支，但 `rebuild.ps1` 固定选择 `fpga_sixpanel`。

该精简包的重建脚本尚未在另一台电脑上实测；随包 `.bit/.hwh` 是已验证的 build22 原件。报告显示 WNS +0.010 ns、WHS +0.008 ns，DRC 与布线错误均为 0。时序裕量很小，板端实测约 2.6 帧/秒。

本项目采用角数阈值进行实验性分类，尚不能作为药材安全鉴别依据。强阴影、遮挡、残缺样品或不同拍摄条件仍需补充验证。早期 CNN 训练、旧版 overlay、临时调参及视频剪辑文件不属于该版本的运行代码，未纳入本包。

`SHA256SUMS.txt` 与 `SOURCE_MANIFEST.json` 是原 build22 精简交付包的快照清单，不覆盖后来补充的 `report/`、`skill/` 与许可说明。报告及上述补充文件以 Git 提交记录为准。
