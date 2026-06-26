#!/bin/bash

set -euo pipefail

#############################################
# APK 安装助手脚本（macOS）
#
# 功能：
# - 所有提示统一通过 macOS 通知中心输出
# - 未传参时支持通过系统文件选择器选择一个或多个 APK
# - 自动检查并定位 adb，可提示 brew 安装
# - 自动检测连接设备；多设备时提供列表选择目标设备
# - 分步通知模拟进度（准备→校验→设备→安装→完成）
# - 全过程日志输出到 /tmp，便于排查
#
# TODO: 如需持久显示进度窗口，可改为配套 AppleScript 进度条窗口。
#############################################

LOG_FILE="/tmp/install_apk_$(date +%s).log"

# 通知工具函数：通过 argv 传参避免转义问题
notify() {
  # 参数：message [title] [subtitle]
  local message="${1:-}"
  local title="${2:-APK安装助手}"
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
  notify "$msg" "APK安装助手" "步骤 ${index}/${total}"
}

# 查找依赖工具
find_bin() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
  elif [ -x "/opt/homebrew/bin/$name" ]; then
    echo "/opt/homebrew/bin/$name"
  elif [ -x "/usr/local/bin/$name" ]; then
    echo "/usr/local/bin/$name"
  else
    echo ""
  fi
}

# 获取设备属性并清理空白字符
get_prop() {
  local serial="$1"
  local key="$2"
  "$ADB_BIN" -s "$serial" shell getprop "$key" 2>/dev/null | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# 构造可读的设备标签：Brand Model • Android X • Serial
build_device_label() {
  local serial="$1"
  local brand model release
  brand="$(get_prop "$serial" ro.product.brand)"
  model="$(get_prop "$serial" ro.product.model)"
  release="$(get_prop "$serial" ro.build.version.release)"
  if [ -z "$brand$model$release" ]; then
    echo "$serial"
  else
    # 使用点分隔提升可读性
    if [ -z "$release" ]; then
      echo "${brand} ${model} • ${serial}"
    else
      echo "${brand} ${model} • Android ${release} • ${serial}"
    fi
  fi
}

TOTAL_STEPS=5

# Step 1: 准备
step 1 "$TOTAL_STEPS" "准备开始安装"
notify "日志: $LOG_FILE" "APK安装助手" "调试信息"

ADB_BIN="$(find_bin adb)"

# Step 2: 检查工具
step 2 "$TOTAL_STEPS" "检查依赖工具"
if [ -z "$ADB_BIN" ]; then
  notify "缺少 adb，请先安装: brew install android-platform-tools" "APK安装助手" "错误"
  exit 1
fi

# Step 3: 选择/校验文件
APK_FILES=()
if [ "$#" -gt 0 ]; then
  for f in "$@"; do
    APK_FILES+=("$f")
  done
else
  notify "未提供APK路径，将弹出文件选择器（可多选）" "APK安装助手" "提示"
  SELECTED=$(/usr/bin/osascript <<'APPLESCRIPT'
set theFiles to choose file with prompt "请选择要安装的APK文件（可多选）" of type {"apk"} with multiple selections allowed true
set out to {}
repeat with f in theFiles
  copy (POSIX path of f) to end of out
end repeat
set text item delimiters of AppleScript to linefeed
return out as text
APPLESCRIPT
  )
  if [ -z "${SELECTED}" ]; then
    notify "未选择文件，已取消" "APK安装助手" "操作已中止"
    exit 1
  fi
  while IFS= read -r line; do
    [ -n "$line" ] && APK_FILES+=("$line")
  done <<EOF
${SELECTED}
EOF
fi

step 3 "$TOTAL_STEPS" "校验文件"
if [ ${#APK_FILES[@]} -eq 0 ]; then
  notify "未获取到任何APK文件" "APK安装助手" "错误"
  exit 1
fi
for f in "${APK_FILES[@]}"; do
  if [ ! -f "$f" ]; then
    notify "文件不存在: $f" "APK安装助手" "错误"
    exit 1
  fi
  if [[ "$f" != *.apk ]]; then
    notify "请选择APK格式的文件: $f" "APK安装助手" "错误"
    exit 1
  fi
done

# Step 4: 设备就绪
step 4 "$TOTAL_STEPS" "检查连接的设备"
"$ADB_BIN" start-server >>"$LOG_FILE" 2>&1 || true

DEVICE_SERIALS=()
while read -r serial state; do
  if [ "$state" = "device" ]; then
    DEVICE_SERIALS+=("$serial")
  fi
done < <("$ADB_BIN" devices | tail -n +2)

DEVICE_COUNT=${#DEVICE_SERIALS[@]}
if [ "$DEVICE_COUNT" -eq 0 ]; then
  notify "未检测到连接的Android设备" "APK安装助手" "错误"
  exit 1
fi

TARGET_SERIAL=""
if [ "$DEVICE_COUNT" -eq 1 ]; then
  TARGET_SERIAL="${DEVICE_SERIALS[0]}"
  notify "已选择设备: $TARGET_SERIAL" "APK安装助手" "设备就绪"
else
  notify "检测到多台设备，将弹出选择" "APK安装助手" "提示"
  # 构造标签数组与并行序列号数组（避免使用 bash 3.2 不支持的关联数组）
  LABELS=()
  SERIALS=()
  for s in "${DEVICE_SERIALS[@]}"; do
    label="$(build_device_label "$s")"
    LABELS+=("$label")
    SERIALS+=("$s")
  done
  # 通过 argv 传给 AppleScript，展示可读标签
  CHOICE_LABEL=$(/usr/bin/osascript - "${LABELS[@]}" <<'APPLESCRIPT'
on run argv
  if (count of argv) is 0 then return ""
  set labels to argv
  set chosen to (choose from list labels with prompt "选择要安装到的设备" OK button name "确定" cancel button name "取消")
  if chosen is false then
    return ""
  else
    return item 1 of chosen
  end if
end run
APPLESCRIPT
  )
  if [ -z "$CHOICE_LABEL" ]; then
    notify "未选择设备，已取消" "APK安装助手" "操作已中止"
    exit 1
  fi
  # 将所选标签映射回序列号
  TARGET_SERIAL=""
  for idx in "${!LABELS[@]}"; do
    if [ "${LABELS[$idx]}" = "$CHOICE_LABEL" ]; then
      TARGET_SERIAL="${SERIALS[$idx]}"
      break
    fi
  done
  # 兜底：若未匹配到，且用户选择的是序列号本身
  if [ -z "$TARGET_SERIAL" ]; then
    for s in "${DEVICE_SERIALS[@]}"; do
      if [ "$s" = "$CHOICE_LABEL" ]; then
        TARGET_SERIAL="$s"
        break
      fi
    done
  fi
  if [ -z "$TARGET_SERIAL" ]; then
    notify "无法识别所选设备，已取消" "APK安装助手" "错误"
    exit 1
  fi
  notify "已选择设备: $CHOICE_LABEL" "APK安装助手" "设备就绪"
fi

# Step 5: 开始安装
step 5 "$TOTAL_STEPS" "开始安装，共 ${#APK_FILES[@]} 个"

SUCCESS_COUNT=0
INDEX=0
for apk in "${APK_FILES[@]}"; do
  INDEX=$((INDEX+1))
  base_name="$(basename "$apk")"
  notify "正在安装(${INDEX}/${#APK_FILES[@]}): ${base_name}" "APK安装助手" "进行中"
  echo "[INFO] Installing to $TARGET_SERIAL: $apk" >>"$LOG_FILE" 2>&1
  set +e
  install_output=$("$ADB_BIN" -s "$TARGET_SERIAL" install -r "$apk" 2>&1)
  status=$?
  set -e
  {
    echo "[INFO] ADB output begin"
    printf "%s\n" "$install_output"
    echo "[INFO] ADB output end"
    echo "[INFO] Install finished ($status): $apk"
  } >>"$LOG_FILE" 2>&1
  if [ $status -eq 0 ]; then
    SUCCESS_COUNT=$((SUCCESS_COUNT+1))
    notify "安装成功: ${base_name}" "安装完成" "${INDEX}/${#APK_FILES[@]}"
  else
    notify "安装失败: ${base_name}，查看日志: $LOG_FILE" "安装出错" "${INDEX}/${#APK_FILES[@]}"
    short_detail=$(truncate_middle "$install_output" 800)
    show_error_dialog "安装出错" "${base_name} 安装失败" "$short_detail"
  fi
done

if [ $SUCCESS_COUNT -eq ${#APK_FILES[@]} ]; then
  notify "全部安装成功（${SUCCESS_COUNT}/${#APK_FILES[@]}）" "安装完成" "成功"
  exit 0
else
  notify "部分/全部失败（${SUCCESS_COUNT}/${#APK_FILES[@]}），日志: $LOG_FILE" "安装出错" "失败"
  exit 1
fi

