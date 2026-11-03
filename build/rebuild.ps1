$ErrorActionPreference='Stop'
$workspace=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ($workspace -match '[^\x00-\x7f]') { throw '请将交付目录解压到不含中文的路径，例如 E:\star_anise_delivery' }
$env:STAR_ANISE_ENGINEERING_ROOT=Join-Path $workspace 'camera_hdmi_720p'
$env:STAR_ANISE_WORKSPACE_ROOT=$workspace
$env:STAR_ANISE_BUILD_TAG='rebuild'
$env:STAR_ANISE_HLS_IP_ROOT=Join-Path $workspace 'camera_hdmi_720p_fpga_sixpanel_delivery\ip_repo\sixpanel_accel'
$env:STAR_ANISE_ISOLATED_DELIVERY=Join-Path $workspace 'rebuild_output\delivery'
$env:STAR_ANISE_ISOLATED_OVERLAY=Join-Path $workspace 'rebuild_output\overlays'
$vivado=Get-Command vivado.bat -ErrorAction Stop
& $vivado.Source -mode batch -source (Join-Path $PSScriptRoot 'build.tcl') -tclargs fpga_sixpanel
if($LASTEXITCODE -ne 0){throw "Vivado failed: $LASTEXITCODE"}
