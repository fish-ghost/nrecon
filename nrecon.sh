#!/bin/bash

# ============================================
# 自动化信息收集脚本（单目标版）
# 用法: ./nrecon.sh <target>
# 功能: 全面收集单个ip的所有信息
# ============================================

set -e  # 遇到错误立即退出
trap 'echo "[!] 脚本被中断。清理临时文件..."; exit 1' INT

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

if [ -z "$1" ]; then
    echo -e "${RED}错误: 请提供目标 IP 或域名。${NC}"
    echo "用法: $0 <target>"
    echo "示例: $0 192.168.1.1"
    echo "示例: $0 example.com"
    exit 1
fi

TARGET="$1"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BASE_DIR="recon_${TARGET}_${TIMESTAMP}"
WAYBACK_FILE="${BASE_DIR}/waybackurls.txt"
DIRSEARCH_DIR="${BASE_DIR}/dirsearch"
JSFINDER_FILE="${BASE_DIR}/jsfinder_output.txt"
WAYMORE_FILE="${BASE_DIR}/waymore_urls.txt"
GAU_FILE="${BASE_DIR}/gau_urls.txt"
BACK_FILE="${BASE_DIR}/back_urls.txt"
KATANA_FILE="${BASE_DIR}/katana_urls.txt"

# 创建输出目录
mkdir -p "$BASE_DIR"
mkdir -p "$DIRSEARCH_DIR"

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1" | tee -a "${BASE_DIR}/scan.log"; }

# 检查命令是否存在的函数
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}错误: 未找到命令 '$1'。请先安装此工具。${NC}"
        exit 1
    fi
}

log "开始对目标 ${YELLOW}${TARGET}${NC} 的信息收集任务。"
log "所有结果将保存在目录: ${BASE_DIR}"

# --- 1. 历史URL抓取 (waybackurls) -----------------------------------------
log "[1/3] 正在获取 Wayback Machine等 历史 URL..."
check_command waybackurls
check_command waymore
check_command gau
for port in 80 443; do
	if [ "$port" -eq 443 ]; then
		PROTO="https"
	else
		PROTO="http"
	fi
	TARGET_URL="${PROTO}://${TARGET}:${port}/"
	echo "$TARGET_URL" | waybackurls >> "$WAYBACK_FILE"
done

waymore -mode U -i "$TARGET" -oU "$WAYMORE_FILE"
gau "$TARGET" >> "$GAU_FILE"

# 去重并排序
cat "$GAU_FILE" "$WAYMORE_FILE" "$WAYBACK_FILE" | sort -u > "$BACK_FILE"
URL_COUNT=$(wc -l < "$BACK_FILE")
log "共收集到 ${URL_COUNT} 条唯一历史 URL。"
log "结果保存在: $BACK_FILE"

# --- 2. Web 目录扫描 (dirsearch) ------------------------------------------
log "[2/3] 正在执行 dirsearch 目录扫描..."

# 扫描 80 和 443 端口
for port in 80 443; do
    if [ "$port" -eq 443 ]; then
        PROTO="https"
    else
        PROTO="http"
    fi
    TARGET_URL="${PROTO}://${TARGET}:${port}/"
    
    log "扫描: $TARGET_URL"
    dirsearch -u "$TARGET_URL" \
        -e php,asp,aspx,jsp,html,js,json,zip,bak,txt \
        -t 30 \
        -o "${DIRSEARCH_DIR}/${TARGET}_${port}.txt" \
        -O plain --quiet
done

log "dirsearch 扫描完成，结果保存在: $DIRSEARCH_DIR"

# --- 3. JS 文件分析 (JSFinder) --------------------------------------------
log "[3/3] 正在执行 JSFinder 分析..."
check_command jsfinder
check_command katana
# 构造完整 URL（如果用户输入没有协议，默认使用 https）
if echo "$TARGET" | grep -qE "^(http://|https://)"; then
    JS_TARGET_URL="$TARGET"
else
    JS_TARGET_URL="https://$TARGET"
fi

log "分析: $JS_TARGET_URL"
{
    echo "===== Results for: $JS_TARGET_URL ====="
    jsfinder -u "$JS_TARGET_URL" -ou - || echo "JSFinder 处理目标失败: $JS_TARGET_URL"
    echo ""
} >> "$JSFINDER_FILE"

log "JSFinder 分析完成，结果保存在: $JSFINDER_FILE"

katana -u "$TARGET" -depth 3 -jc -kf all -aff -sb -sc -jsl -ct 30m -c 5 -rate-limit 5 -fx -no-scope -f url,path -o "$KATANA_FILE"

log "katana 分析完成结果保存在: $KATANA_FILE"

# --- 总结 -------------------------------------------------------------
echo -e """
${GREEN}========================================${NC}
      ${GREEN}✅ 信息收集任务完成！${NC}
${GREEN}========================================${NC}
目标: ${YELLOW}${TARGET}${NC}
输出目录: ${YELLOW}${BASE_DIR}${NC}
历史URL:  ${BACK_FILE} (${URL_COUNT} 条)
目录扫描: ${DIRSEARCH_DIR}
JS分析:   ${JSFINDER_FILE} ${KATANA_FILE}
完整日志: ${BASE_DIR}/scan.log
"""
