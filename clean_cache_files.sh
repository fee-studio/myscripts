#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# 定义要搜索的大文件路径 - 主要包含安全且推荐定期清理的目录
SEARCH_PATHS=(
    # 应用缓存文件
    "$HOME/Library/Caches/"
    "/Library/Caches/"
    
    # 下载文件夹
    "$HOME/Downloads/"
    
    # 日志文件
    "$HOME/Library/Logs/"
    "/Library/Logs/"
    "/var/log/"
    
    # 应用残留文件
    "$HOME/Library/Application Support/"
    "$HOME/Library/Preferences/"
    "$HOME/Library/Containers/"
    
    # iOS 设备备份
    "$HOME/Library/Application Support/MobileSync/Backup/"
    
    # Xcode 相关可清理文件
    "$HOME/Library/Developer/Xcode/DerivedData/"
    "$HOME/Library/Developer/Xcode/iOS DeviceSupport/"
    
    # 用户常见数据目录
    # "$HOME/Documents/"
    "$HOME/Desktop/"
    # "$HOME/Movies/"
    # "$HOME/Music/"
    # "$HOME/Pictures/"
    
    # 系统临时文件
    "/var/tmp/"
    "$HOME/Library/Caches/TemporaryItems/"
    
    # 开发工具相关
    "$HOME/.m2/"
    "$HOME/.gradle/"
    "$HOME/.npm/"
    "$HOME/.yarn/"
)

# 定义要搜索的文件模式（包括hprof及其他常见大文件类型）
PATTERNS=(
    "*.hprof*"         # Java内存快照
    "*.log*"           # 日志文件
    "*.tmp"            # 临时文件
    "*.cache*"         # 缓存文件
    "*.bak"            # 备份文件
    "*.dmg"            # 安装镜像
    "*.iso"            # 光盘镜像
    # "*.zip"            # 压缩包
    # "*.tar*"           # 压缩包
    # "*.gz"             # 压缩包
    # "*.7z"             # 压缩包
    "*.pkg"            # 安装包
    "*.ipsw"           # iOS固件
)

# 最小文件大小（MB），只搜索超过此大小的文件（默认 10MB）
MIN_SIZE="1"

# 是否忽略扩展名（搜索所有大文件）
ALL_FILES=false
# 调试模式
DEBUG=false

# 简易使用说明
usage() {
    cat <<EOF
用法: $(basename "$0") [-s MB] [--all] [--debug]

选项:
  -s MB     设置大小阈值，单位MB，默认 500
  --all     不按照扩展名过滤，搜索所有超过阈值的文件
  -h        显示帮助
  --debug   打印调试信息（当前匹配表达式等）

示例:
  $(basename "$0")                 # 搜索常见可清理类型，>500MB
  $(basename "$0") -s 200          # 搜索常见可清理类型，>200MB
  $(basename "$0") --all -s 1024   # 搜索所有类型，>1GB
EOF
}

# 解析参数
while (( "$#" )); do
    case "$1" in
        -s)
            shift
            [[ -n "${1:-}" ]] || { echo "缺少 -s 的参数" >&2; exit 1; }
            MIN_SIZE="$1"
            shift
            ;;
        --all)
            ALL_FILES=true
            shift
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        -h|--help)
            usage; exit 0
            ;;
        --) shift; break ;;
        -*) echo "未知参数: $1" >&2; usage; exit 1 ;;
        *) break ;;
    esac
done

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 颜色定义和提示信息
echo -e "${BLUE}=== 大文件搜索与清理工具 ===${NC}"
echo -e "${YELLOW}搜索范围：${NC}系统中可安全清理的目录"
if [ "$ALL_FILES" = true ]; then
    echo -e "${YELLOW}搜索条件：${NC}大于 ${MIN_SIZE}MB 的所有类型文件"
else
    echo -e "${YELLOW}搜索条件：${NC}大于 ${MIN_SIZE}MB 的常见可清理文件类型"
fi
echo -e "${BLUE}==========================================${NC}"

# 临时文件用于收集结果
TMP_FILE=$(mktemp)
cleanup() { rm -f "$TMP_FILE" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

# 计数器
FILE_COUNT=0
TOTAL_SIZE=0

# 构建 find 的模式表达式（仅在非 --all 时生效）
FIND_EXPR=()
if [ "$ALL_FILES" = false ]; then
    first=true
    for pattern in "${PATTERNS[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            FIND_EXPR+=(-o)
        fi
        FIND_EXPR+=(-iname "$pattern")
    done
fi

if [ "$DEBUG" = true ] && [ "$ALL_FILES" = false ]; then
    echo "[DEBUG] MIN_SIZE=${MIN_SIZE}MB"
    printf "[DEBUG] FIND_EXPR tokens (%d):\n" ${#FIND_EXPR[@]}
    printf '  %q\n' "${FIND_EXPR[@]}"
fi

echo -e "${YELLOW}开始搜索大文件...${NC}"

# 将字节数转换为人类可读
human_bytes() {
    local bytes="$1"
    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec-i --suffix=B "$bytes"
    else
        awk -v b="$bytes" '
            function hr(x){
                s[0]="B"; s[1]="KiB"; s[2]="MiB"; s[3]="GiB"; s[4]="TiB"; s[5]="PiB";
                i=0; while (x>=1024 && i<5){x/=1024; i++}
                printf("%.1f%s", x, s[i])
            }
            BEGIN { hr(b) }
        '
    fi
}

# 遍历每个目录进行搜索
for path in "${SEARCH_PATHS[@]}"; do
    if [ -d "$path" ] && [ -r "$path" ]; then
        echo -e "${GREEN}正在搜索:${NC} $path"
        if [ "$ALL_FILES" = true ]; then
            { find "$path" -type f -size +"${MIN_SIZE}"M -print0 2>/dev/null || true; } |
            while IFS= read -r -d '' file; do
                mtime=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$file")
                byte_size=$(stat -f "%z" "$file")
                size_hr=$(human_bytes "$byte_size")
                echo "$byte_size|$size_hr|$mtime|$file" >> "$TMP_FILE"
            done
        else
            # 使用模式过滤：将模式用括号分组，默认与 -type f 和 -size 一起按 AND 组合
            { find "$path" -type f \( "${FIND_EXPR[@]}" \) -size +"${MIN_SIZE}"M -print0 2>/dev/null || true; } |
            while IFS= read -r -d '' file; do
                mtime=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$file")
                byte_size=$(stat -f "%z" "$file")
                size_hr=$(human_bytes "$byte_size")
                echo "$byte_size|$size_hr|$mtime|$file" >> "$TMP_FILE"
            done
        fi
    fi
done

# 计算统计信息
if [ -s "$TMP_FILE" ]; then
    FILE_COUNT=$(wc -l < "$TMP_FILE")
    TOTAL_SIZE=$(awk -F'|' '{sum+=$1} END {print sum}' "$TMP_FILE")
    TOTAL_SIZE_HUMAN=$(human_bytes "$TOTAL_SIZE")
fi

# 显示搜索结果和统计信息
if [ -s "$TMP_FILE" ]; then
    echo -e "\n${BLUE}==========================================${NC}"
    echo -e "${GREEN}搜索完成！${NC}"
    echo -e "${YELLOW}找到文件数量:${NC} $FILE_COUNT 个"
    echo -e "${YELLOW}总大小:${NC} $TOTAL_SIZE_HUMAN"
    echo -e "${BLUE}==========================================${NC}"

    while true; do
        # 询问操作模式
        echo -e "\n${YELLOW}请选择操作模式:${NC}"
        echo "1) 逐个文件确认删除"
        echo "2) 显示所有文件列表"
        echo "3) 批量删除所有文件（谨慎使用）"
        echo "4) 退出"

        read -r -p "请输入选择 [1-4]: " choice

        case $choice in
            1)
                echo -e "\n${BLUE}开始逐个确认删除...${NC}"
                deleted_count=0
                deleted_size=0

                # 将排序结果存储到数组中，避免管道问题
                declare -a files_array
                while IFS='|' read -r byte_size size mtime file; do
                    files_array+=("$byte_size|$size|$mtime|$file")
                done < <(sort -t '|' -k1,1nr "$TMP_FILE")

                # 遍历文件数组
                for file_info in "${files_array[@]}"; do
                    IFS='|' read -r byte_size size mtime file <<< "$file_info"
                    echo -e "\n${BLUE}------------------------------------------${NC}"
                    echo -e "${YELLOW}大小:${NC} $size"
                    echo -e "${YELLOW}修改时间:${NC} $mtime"
                    echo -e "${YELLOW}路径:${NC} $file"

                    read -p "是否删除此文件? [y/N/q(退出)]: " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Qq]$ ]]; then
                        echo -e "${YELLOW}用户取消操作${NC}"
                        break
                    elif [[ $REPLY =~ ^[Yy]$ ]]; then
                        if [ -f "$file" ]; then
                            if rm -f "$file" 2>/dev/null; then
                                echo -e "${GREEN}✓ 已删除:${NC} $file"
                                ((deleted_count++))
                                deleted_size=$((deleted_size + byte_size))
                            else
                                echo -e "${RED}✗ 删除失败（权限不足）:${NC} $file"
                            fi
                        else
                            echo -e "${RED}✗ 文件不存在:${NC} $file"
                        fi
                    else
                        echo -e "${BLUE}跳过:${NC} $file"
                    fi
                done

                # 显示删除统计
                if [ $deleted_count -gt 0 ]; then
                    deleted_size_human=$(human_bytes "$deleted_size")
                    echo -e "\n${GREEN}删除完成！${NC}"
                    echo -e "${YELLOW}删除文件数:${NC} $deleted_count"
                    echo -e "${YELLOW}释放空间:${NC} $deleted_size_human"
                fi
                ;;

            2)
                echo -e "\n${BLUE}文件列表（按大小降序）:${NC}"
                echo -e "${BLUE}==========================================${NC}"
                sort -t '|' -k1,1nr "$TMP_FILE" | cut -d'|' -f2- | while IFS='|' read -r size mtime file; do
                    echo -e "${YELLOW}$size${NC} | $mtime | $file"
                done
                ;;

            3)
                echo -e "\n${RED}警告: 这将删除所有找到的 ${FILE_COUNT} 个文件（总计 ${TOTAL_SIZE_HUMAN}）！${NC}"
                read -p "确定要继续吗？输入 'DELETE' 确认: " confirm
                if [ "$confirm" = "DELETE" ]; then
                    deleted_count=0
                    deleted_size=0
                    while IFS='|' read -r byte_size size mtime file; do
                        if [ -f "$file" ]; then
                            if rm -f "$file" 2>/dev/null; then
                                echo -e "${GREEN}✓ 删除:${NC} $file ($size)"
                                ((deleted_count++))
                                deleted_size=$((deleted_size + byte_size))
                            else
                                echo -e "${RED}✗ 删除失败:${NC} $file"
                            fi
                        fi
                    done < <(sort -t '|' -k1,1nr "$TMP_FILE")

                    deleted_size_human=$(human_bytes "$deleted_size")
                    echo -e "\n${GREEN}批量删除完成！${NC}"
                    echo -e "${YELLOW}删除文件数:${NC} $deleted_count"
                    echo -e "${YELLOW}释放空间:${NC} $deleted_size_human"
                else
                    echo -e "${YELLOW}取消批量删除操作${NC}"
                fi
                ;;

            4)
                echo -e "${YELLOW}退出程序${NC}"
                break
                ;;

            *)
                echo -e "${RED}无效选择${NC}"
                ;;
        esac
    done
else
    echo -e "\n${YELLOW}未找到大于 ${MIN_SIZE}MB 的可清理文件。${NC}"
fi

# 清理临时文件
rm -f "$TMP_FILE"

echo -e "\n${GREEN}程序执行完成！${NC}"
    