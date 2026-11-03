# PYNQ-Z1 摄像头六画面工程交付说明

本包对应已加载到板端的 build22，器件 xc7z020clg400-1，Vivado/Vitis 2026.1，板端 PYNQ 3.1.1。采集 OV5640 RGB565，显示 720p 六画面；不使用 CNN。

## 目录

- `board/overlays/`：同名 bit/hwh 和板端 Python/启动程序。
- `_vivado_fpga_sixpanel_build22/`：当次实现的 Vivado 工程及生成文件。
- `camera_hdmi_720p/`：板卡、约束、摄像头及 HDMI 依赖源码。
- `camera_hdmi_720p_fpga_sixpanel/`：HLS 图像处理、分类器和参考 Python；`camera_hdmi_720p_fpga_sixpanel_delivery/ip_repo/` 包含打包的 HLS IP。
- `camera_hdmi_720p_python_sixpanel_delivery/hdmi_vga_axis_raster.v`：实际使用的 HDMI 显示与文字叠加模块。
- `reports_and_build_delivery/`：实际构建的报告、源码副本和 IP；其 `two_view_menu` 命名为历史构建名，board 目录文件才是当前六画面运行名。
- `build/`：Tcl 和 Windows 重建脚本；`verification/`：相关检查代码及之前一次帧缓冲截图。

## 上板运行

将 `board/overlays/` 内容复制到 `/home/xilinx/jupyter_notebooks/star_anise_fpga/overlays/`。在板端执行 `sudo bash /home/xilinx/jupyter_notebooks/star_anise_fpga/overlays/fpga_sixpanel_support/start_board_fpga_sixpanel.sh`。BTN0 按一次锁存显示分类，再按一次返回 WAIT；角数小于 10 显示八角，10 及以上显示莽草，无效结果显示 NONE。

## 重建

解压到不含中文的短路径，在 Vivado 2026.1 环境中执行 `build/rebuild.ps1`。也可打开目录中 xpr；为降低绝对路径依赖已重写项目中的 HLS IP 路径。重建脚本和搬迁后的 xpr 尚未在第二台电脑实测，生成的 bit/hwh 以随包交付的文件为准。重新综合 HLS 时原 `build_hls.ps1` 含本机 E 盘路径，需按安装路径修改。

## 验证与限制

本次 bit SHA256 `0730133b1eaee2c81c32f1bb69883b3b4ab15eb85c4a4e154c69c5f27f5ee8a5`，hwh SHA256 `7d5f4d0ccbd9ea41fb5fe5376d032763f89c8b8abdab4f381187739d09ad7245`，与板端一致。实现 WNS +0.010 ns、WHS +0.008 ns、TNS/THS 0，DRC error 0、布线错误 0；时序裕量很小。按钮阈值与锁存经过仿真，实体按键和屏幕文字未能从帧缓冲核验，需实板观察。板端约 2.6 帧/秒，非摄像头全帧率；真实强阴影、遮挡下分割与角数可能失准。板端截图不含 HDMI 后级文字叠加。

原 Python 参考与当前 HLS 包含近似及有意优化，不能声称逐像素一致。形状角数规则是实验算法，未在足够多独立样品上验证。

板端摄像头初始化脚本已从实际运行板读取并校验 SHA256 `17b84fe8c7af780ec2f64364106e1eb3e77f2e2bf72becc67a190971bbd7419c`；它与工程目录的旧参考副本不同，部署时以 board 目录为准。verification 中部分 C++ 检查包含原机器绝对路径，迁移后需修改 include。
