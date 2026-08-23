#!/usr/bin/env bash
#
# 把 em_proxy 的预编译产物钉在一个固定的 release tag 上。
#
# 为什么需要这个:em_proxy 的产物不在版本库里,是构建时下载的。子模块自带的
# fetch-prebuilt.sh 写死了 `releases/latest`,而上游 2026-08-12 发的 v0.9.2 把
# 产物从四个散件换成了单个 EMProxy.xcframework.zip —— 老名字全部 404。
#
# 真正的杀伤力在于那个脚本用的是 `wget -O`:下载失败照样把目标文件截成 0 字节,
# 退出码还是 0。于是 em_proxy.swift 变成空文件,编译时报
#
#     module 'em_proxy' has no member named 'start_em_proxy'
#
# 看起来像代码问题,其实是一次静默的网络失败。这个脚本反过来:任何一步不对就
# 立刻用非零退出码停下,绝不留下半成品。
#
# 本地也能跑。跑一次之后 .skip-prebuilt-fetch-em_proxy 会让子模块的脚本永远
# 跳过,Xcode 构建时不再碰网络。
set -euo pipefail

# 上游改格式之前的滚动 tag。四个资产都还在,也正是 v0.6.4-xigua.25 当时下到的
# 那份。要升级就改这里,并且确认新 tag 确实带着下面 FILES 里的全部文件。
readonly TAG="${EM_PROXY_TAG:-build}"
readonly BASE="https://github.com/SideStore/em_proxy/releases/download/${TAG}"
readonly FILES=(em_proxy.h em_proxy.swift libem_proxy-ios.a libem_proxy-sim.a)

# 下载成功后要在 em_proxy.swift 里找到的符号。上游再换产物形状时,靠这个立刻
# 发现,而不是等编译器报一句看不出根因的错。
readonly SENTINEL="func start_em_proxy"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly dest="${repo_root}/Dependencies/em_proxy"

# CI 上用 ::error:: 让注解落在 Actions 的摘要里;本地就普通打印。
err() {
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error::$*" >&2
  else
    echo "error: $*" >&2
  fi
}

if [[ ! -d "$dest" ]]; then
  err "找不到 $dest —— 子模块没检出?试 git submodule update --init --recursive"
  exit 1
fi

cd "$dest"

for f in "${FILES[@]}"; do
  # 先下到临时文件,校验通过再就位。中途失败不会留下一个空的/半截的产物,
  # 否则下一次构建会拿着坏文件继续跑。
  tmp="${f}.download"
  if ! curl -fsSL --retry 3 --retry-delay 2 -o "$tmp" "${BASE}/${f}"; then
    rm -f "$tmp"
    err "下载失败: ${BASE}/${f}"
    exit 1
  fi
  if [[ ! -s "$tmp" ]]; then
    rm -f "$tmp"
    err "${f} 下下来是空的: ${BASE}/${f}"
    exit 1
  fi
  mv "$tmp" "$f"
  echo "  ${f}: $(wc -c < "$f" | tr -d ' ') bytes"
done

if ! grep -q "$SENTINEL" em_proxy.swift; then
  err "em_proxy.swift 里没有 '${SENTINEL}' —— 上游 '${TAG}' 的产物形状变了"
  exit 1
fi

# 让子模块的 fetch-prebuilt.sh 直接返回,不再去 releases/latest 碰运气。
touch .skip-prebuilt-fetch-em_proxy

echo "em_proxy 已钉在 tag '${TAG}'"
