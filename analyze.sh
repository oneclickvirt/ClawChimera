#!/usr/bin/env bash
# =============================================================================
# analyze.sh — ClawChimera ECS 测试结果 AI 分析工具
#
# 读取 goecs.txt（ECS 融合怪测试结果文件），内嵌各项指标评判标准（来源于
# https://github.com/oneclickvirt/ecs/blob/master/README_NEW_USER.md），
# 生成结构化的 AI 分析提示词，帮助提取 VPS 的优点与不足。
#
# 用法:
#   bash analyze.sh                  # 将提示词打印到 stdout（可粘贴到任意 AI 对话）
#   bash analyze.sh -f myresult.txt  # 指定结果文件（默认 ./goecs.txt）
#   bash analyze.sh --call-ai        # 自动调用本地 AI 工具（llm / aichat / ollama）
#   bash analyze.sh --copy           # 将提示词复制到剪贴板（需 xclip/pbcopy）
# =============================================================================
set -euo pipefail

# ── 解析参数 ──────────────────────────────────────────────────────────────────
RESULT_FILE="./goecs.txt"
CALL_AI=false
COPY_CLIP=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--file)    RESULT_FILE="$2"; shift 2 ;;
        --call-ai)    CALL_AI=true;  shift ;;
        --copy)       COPY_CLIP=true; shift ;;
        -h|--help)
            grep '^#' "$0" | grep -v '^#!' | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "未知参数: $1" >&2; exit 1 ;;
    esac
done

# ── 检查结果文件 ──────────────────────────────────────────────────────────────
if [[ ! -f "$RESULT_FILE" ]]; then
    echo -e "\033[31m[analyze]\033[0m 未找到结果文件: $RESULT_FILE" >&2
    echo -e "\033[33m[analyze]\033[0m 请先运行 bash run.sh 执行 ECS 测试，结果将保存到 goecs.txt" >&2
    exit 1
fi

RESULT_CONTENT=$(cat "$RESULT_FILE")
if [[ -z "$RESULT_CONTENT" ]]; then
    echo -e "\033[31m[analyze]\033[0m 结果文件为空: $RESULT_FILE" >&2
    exit 1
fi

# ── 构建提示词 ────────────────────────────────────────────────────────────────
# 内嵌完整的 ECS 指标评判标准（来源于 README_NEW_USER.md 及上游文档）
build_prompt() {
cat <<'PROMPT_EOF'
你是一位专业的 VPS 服务器评测专家，精通中国大陆网络环境、服务器硬件性能基准和网络质量分析。

请根据以下【评判标准】对【ECS 融合怪测试结果】进行全面分析，提取该 VPS 的**优点**和**不足**，
并给出综合评价和适用场景建议。

========== 【ECS 评判标准】==========

## CPU 性能（sysbench 单线程得分）
- 5000+    : 第一档 · 旗舰级（AWS c7g、最新 Xeon/EPYC）
- 4000~4999: 第二档 · 高性能（Xeon Platinum、Apple M 系列）
- 3000~3999: 第三档 · 中高性能（Xeon Gold、EPYC 7xxx）
- 2000~2999: 第四档 · 主流（Xeon E5 v4、普通 KVM VPS 主流）
- 1000~1999: 第五档 · 入门级
- <1000    : 第六档 · 低性能（超售严重或低端硬件）
- geekbench5 单核  >1500 高性能，>1000 主流，<800 低性能

## 内存带宽（STREAM 测试）
- Triad >50 GB/s : DDR5 或高频多通道，非常优秀
- Triad 20~50 GB/s: DDR4 主流水平
- Triad <20 GB/s : DDR3 或单通道/低频，偏慢
- Copy  >40 GB/s : 优秀；<10 GB/s 偏慢

## 磁盘 IO（fio 测试）
### 4K 随机读写（IOPS）
- 随机读  >200000 IOPS: NVMe 高端（优秀）
- 随机读  50000~200000: NVMe 普通
- 随机读  10000~50000 : SATA SSD
- 随机读  <5000 IOPS  : HDD 或超慢网络存储
### 顺序 1M 读写（吞吐）
- >2 GB/s : NVMe 高端
- >500 MB/s: SSD 主流
- <200 MB/s: 较慢，可能为共享网络存储（Ceph/NFS）

## 网络测速
### 下载速度
- >500 Mbps : 优秀（适合大流量业务）
- 100~500 Mbps: 良好
- <50 Mbps   : 较慢，不适合下载密集型业务
### 上传速度
- 标准判断与下载相同
### 测速节点：中国三网（CMCC移动/CU联通/CT电信）及国际
- 三网均有节点且速度平衡：国内外业务均适用
- 仅国际节点快：适合面向海外用户
- 三网差异极大：可能存在不对等路由或限速

## 流媒体解锁
- Netflix 全解锁（非 DNS 解锁）: 高价值，说明 IP 为原生解锁地区 IP
- Netflix 仅自制内容            : 一般
- Disney+ 解锁                 : 高价值
- ChatGPT / OpenAI 可用        : 高价值（国内封锁严）
- 主要平台均可用：解锁能力强，适合代理/流媒体节点
- 均不可用：IP 可能被广泛封锁

## IP 质量
- 欺诈评分（Fraud Score）: <20 优秀；20~60 中等；>60 风险较高
- 数据中心 IP（datacenter）: 大多数 VPS 均为此类，正常
- 住宅 IP（residential）  : 稀有且高价值，解锁能力极强
- 滥用数据库（AbuseIPDB）命中率高: IP 历史较差，可能被部分服务拒绝
- AS 信息: 大型 ISP（Hurricane Electric、Cogent等）资源充足

## 邮件端口
- 25 端口开放  : 可发送原始 SMTP 邮件（大多数 VPS 已封锁）
- 465/587 开放 : 可使用 TLS/STARTTLS 加密邮件，常规需求可满足
- 全部封锁     : 无法自建邮件服务器

## 回程路由（Backtrace）
- 直连三网（不经 NTT/Zayo/GTT 等绕行）: 网络延迟低，优秀
- 经过 NTT/GTT/PCCW 等绕行            : 延迟较高，一般
- 电信 CN2 GIA/GT                       : CN2 GIA 最优，延迟低稳定
- 联通 AS4837 直连                      : 优秀
- 移动 CMI 直连                         : 优秀
- 回程绕美（经美国节点中转）: 延迟极高，不适合国内用户

## 三网延迟（NT3 测试）
- 平均延迟 <80ms  : 极优（香港/日本节点）
- 平均延迟 80~150ms: 良好（新加坡/美西）
- 平均延迟 150~200ms: 一般（美东/欧洲）
- 平均延迟 >200ms : 较差，不适合延迟敏感业务

## 综合路由质量
- 去程：如 BGP 多线接入 / 163 / CN2 / CMIN2
- 回程：CN2 GIA > 联通直连 > 移动直连 > 163 > 绕行美国

========== 【ECS 测试结果】==========
PROMPT_EOF

echo "$RESULT_CONTENT"

cat <<'PROMPT_EOF2'

========== 【分析要求】==========

请按以下格式输出分析报告：

## 基本信息
（服务商/机房位置/虚拟化类型/配置概览）

## ✅ 优点
（逐条列出，每条说明原因和实际影响）

## ❌ 不足
（逐条列出，每条说明严重程度和对使用的影响）

## 📊 各项评分（满分10分）
| 项目 | 得分 | 简评 |
|---|---|---|
| CPU 性能 | x/10 | |
| 内存带宽 | x/10 | |
| 磁盘 IO | x/10 | |
| 网络速度 | x/10 | |
| 网络延迟 | x/10 | |
| 流媒体解锁 | x/10 | |
| IP 质量 | x/10 | |
| 路由质量 | x/10 | |

## 🎯 适用场景
（根据综合表现，推荐最适合的1~3种用途）

## 💡 综合建议
（总结性评语，是否物有所值，注意事项）
PROMPT_EOF2
}

PROMPT=$(build_prompt)

# ── 输出处理 ──────────────────────────────────────────────────────────────────

# 复制到剪贴板
if [[ "$COPY_CLIP" == "true" ]]; then
    if command -v xclip &>/dev/null; then
        echo "$PROMPT" | xclip -selection clipboard
        echo -e "\033[32m[analyze]\033[0m 提示词已复制到剪贴板（xclip）" >&2
    elif command -v xsel &>/dev/null; then
        echo "$PROMPT" | xsel --clipboard --input
        echo -e "\033[32m[analyze]\033[0m 提示词已复制到剪贴板（xsel）" >&2
    elif command -v pbcopy &>/dev/null; then
        echo "$PROMPT" | pbcopy
        echo -e "\033[32m[analyze]\033[0m 提示词已复制到剪贴板（pbcopy）" >&2
    else
        echo -e "\033[33m[analyze]\033[0m 未找到剪贴板工具（xclip/xsel/pbcopy），直接打印：" >&2
        echo "$PROMPT"
    fi
    exit 0
fi

# 调用本地 AI 工具
if [[ "$CALL_AI" == "true" ]]; then
    if command -v llm &>/dev/null; then
        echo -e "\033[36m[analyze]\033[0m 使用 llm 工具分析..." >&2
        echo "$PROMPT" | llm
    elif command -v aichat &>/dev/null; then
        echo -e "\033[36m[analyze]\033[0m 使用 aichat 工具分析..." >&2
        echo "$PROMPT" | aichat
    elif command -v ollama &>/dev/null; then
        MODEL="${OLLAMA_MODEL:-llama3}"
        echo -e "\033[36m[analyze]\033[0m 使用 ollama ($MODEL) 分析..." >&2
        echo "$PROMPT" | ollama run "$MODEL"
    else
        echo -e "\033[33m[analyze]\033[0m 未找到本地 AI 工具（llm / aichat / ollama）" >&2
        echo -e "\033[33m[analyze]\033[0m 提示词已打印，请手动粘贴到 AI 对话：" >&2
        echo ""
        echo "$PROMPT"
    fi
    exit 0
fi

# 默认：打印提示词
echo "$PROMPT"
echo "" >&2
echo -e "\033[36m[analyze]\033[0m 提示词已生成。" >&2
echo -e "\033[36m[analyze]\033[0m 💡 将上方内容粘贴到 ChatGPT / Claude / Gemini 等 AI 对话中即可获得分析报告。" >&2
echo -e "\033[36m[analyze]\033[0m 💡 使用 --copy 参数可直接复制到剪贴板，--call-ai 可调用本地 AI 工具。" >&2
