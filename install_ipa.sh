#!/bin/bash

set -euo pipefail

#############################################
# IPA 安装助手脚本（macOS）
#
# 变更说明：
# - 所有提示统一通过 macOS 通知中心（osascript display notification）输出
# - 支持未传参时通过系统文件选择器选择 IPA 文件
# - 增加工具可用性检查与更友好的失败提示
# - 用分步通知模拟安装进度（准备→校验→设备→安装→完成）
#
# 注意：通知中心不支持原生进度条，这里通过分步骤通知进行“进度感知”。
# TODO: 如需更细粒度的实时进度，可改为配套一个常驻的 AppleScript 进度窗口。
#############################################

LOG_FILE="/tmp/install_ipa_$(date +%s).log"

# 通知工具函数：通过 argv 传参避免转义问题
notify() {
  # 参数：message [title] [subtitle]
  local message="${1:-}"
  local title="${2:-IPA安装助手}"
  local subtitle="${3:-}"
  /usr/bin/osascript - "$message" "$title" "$subtitle" >>"$LOG_FILE" 2>&1 <<'APPLESCRIPT'
on run argv
  set theMessage to item 1 of argv
  set theTitle to item 2 of argv
  set theSubtitle to ""
  if (count of argv) ≥ 3 then set theSubtitle to item 3 of argv
  try
    if theSubtitle is equal to "" then
      display notification theMessage with title theTitle sound name "default"
    else
      display notification theMessage with title theTitle subtitle theSubtitle sound name "default"
    end if
  end try
end run
APPLESCRIPT
}

# 错误对话框：展示失败原因并提供打开日志按钮
show_error_dialog() {
  # 参数：title header detail
  local title="${1:-安装出错}"
  local header="${2:-安装失败}"
  local detail="${3:-}"
  /usr/bin/osascript - "$title" "$header" "$detail" "$LOG_FILE" >>"$LOG_FILE" 2>&1 <<'APPLESCRIPT'
on run argv
  set theTitle to item 1 of argv
  set theHeader to item 2 of argv
  set theDetail to item 3 of argv
  set theLog to item 4 of argv
  set msg to theHeader & "\n\n" & theDetail
  try
    display dialog msg with title theTitle buttons {"确定", "打开日志"} default button "确定"
    set btn to button returned of result
    if btn is "打开日志" then
      do shell script "open " & quoted form of theLog
    end if
  end try
end run
APPLESCRIPT
}

# 截断文本，避免对话框过长
truncate_middle() {
  local text="$1"
  local max=${2:-800}
  local len=${#text}
  if [ "$len" -le "$max" ]; then
    printf "%s" "$text"
  else
    local half=$((max/2))
    printf "%s\n...\n%s" "${text:0:half}" "${text: -half}"
  fi
}

# 以步骤形式输出“进度”通知
step() {
  # 参数：stepIndex/stepTotal message
  local index="$1"; shift
  local total="$1"; shift
  local msg="$*"
  notify "$msg" "IPA安装助手" "步骤 ${index}/${total}"
}

# 查找依赖工具，兼容 Homebrew/系统路径
find_bin() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
  elif [ -x "/opt/homebrew/bin/$name" ]; then
    echo "/opt/homebrew/bin/$name"
  elif [ -x "/usr/local/bin/$name" ]; then
    echo "/usr/local/bin/$name"
  else
    echo ""  # 未找到
  fi
}

IDEVICE_ID_BIN="$(find_bin idevice_id)"
IDEVICEINSTALLER_BIN="$(find_bin ideviceinstaller)"

TOTAL_STEPS=5

# Step 1: 准备/选择文件
step 1 "$TOTAL_STEPS" "准备开始安装"

IPA_PATH="${1-}"
if [ -z "${IPA_PATH}" ]; then
  notify "未提供IPA路径，将弹出文件选择器" "IPA安装助手" "提示"
  # 通过系统文件选择器选择 IPA 文件
  if ! IPA_PATH=$( /usr/bin/osascript <<'APPLESCRIPT'
set f to choose file with prompt "请选择要安装的IPA文件" of type {"ipa"}
POSIX path of f
APPLESCRIPT
  ); then
    notify "未选择文件，已取消" "IPA安装助手" "操作已中止"
    exit 1
  fi
fi

# 记录日志文件位置，便于排查
notify "日志: $LOG_FILE" "IPA安装助手" "调试信息"

# Step 2: 校验文件
step 2 "$TOTAL_STEPS" "校验文件"
if [ ! -f "$IPA_PATH" ]; then
  notify "文件不存在: $IPA_PATH" "IPA安装助手" "错误"
  exit 1
fi
if [[ "$IPA_PATH" != *.ipa ]]; then
  notify "请选择IPA格式的文件" "IPA安装助手" "错误"
  exit 1
fi

# Step 3: 检查工具可用性
step 3 "$TOTAL_STEPS" "检查依赖工具"
if [ -z "$IDEVICE_ID_BIN" ]; then
  notify "缺少 idevice_id，请先安装: brew install libimobiledevice" "IPA安装助手" "错误"
  exit 1
fi
if [ -z "$IDEVICEINSTALLER_BIN" ]; then
  notify "缺少 ideviceinstaller，请先安装: brew install ideviceinstaller" "IPA安装助手" "错误"
  exit 1
fi

# Step 4: 检测设备
step 4 "$TOTAL_STEPS" "检查连接的设备"
DEVICE_COUNT=$("$IDEVICE_ID_BIN" -l | wc -l | tr -d ' ')
if [ "${DEVICE_COUNT}" = "0" ]; then
  notify "未检测到连接的iOS设备" "IPA安装助手" "错误"
  exit 1
fi
notify "检测到 ${DEVICE_COUNT} 台设备" "IPA安装助手" "设备就绪"

# Step 5: 开始安装
step 5 "$TOTAL_STEPS" "开始安装"
notify "正在安装: $(basename "$IPA_PATH")，请稍候…" "IPA安装助手" "进行中"

echo "[INFO] Start install: $IPA_PATH" >>"$LOG_FILE" 2>&1
# 暂时关闭 set -e 以捕获安装返回码
set +e
install_output=$("$IDEVICEINSTALLER_BIN" -i "$IPA_PATH" 2>&1)
INSTALL_STATUS=$?
set -e
{
  echo "[INFO] ideviceinstaller output begin"
  printf "%s\n" "$install_output"
  echo "[INFO] ideviceinstaller output end"
  echo "[INFO] Install command finished with status $INSTALL_STATUS"
} >>"$LOG_FILE" 2>&1
if [ $INSTALL_STATUS -eq 0 ]; then
  notify "IPA安装成功" "安装完成" "已成功安装"
  exit 0
else
  notify "IPA安装失败，请查看日志: $LOG_FILE" "安装出错" "失败"
  short_detail=$(truncate_middle "$install_output" 800)
  show_error_dialog "安装出错" "安装失败: $(basename "$IPA_PATH")" "$short_detail"
  exit 1
fi
