#!/usr/bin/env bash
# 조직별 북마크 카드 SVG(org-*.svg) 생성기.
# - GitHub API에서 공개/비공개 리포 수를 읽어 카드 우하단에 표시한다.
# - 비공개 수(total_private_repos)는 조직 접근 권한이 있는 토큰(GH_TOKEN)이 있어야 나온다.
#   토큰이 없으면 공개 수만 표시한다.
# - 아바타는 base64로 SVG에 내장한다(외부 이미지는 <img> 임베드에서 로드되지 않음).
# - 라이트 팔레트 기본 + @media(prefers-color-scheme: dark) 오버라이드.
# 설계 배경과 정책은 저장소 루트 PROJECT.md 참고.
set -euo pipefail

# 저장소 루트에서 실행해도, scripts/에서 실행해도 동작하도록 출력 위치를 고정한다
cd "$(dirname "$0")/.."

orgs=(siakun-private siakun-testing siakun-archive siakun-forks)
shorts=(private testing archive forks)
# 설명은 카드 한 줄에 들어가는 길이로 유지한다 (아바타 제외 유효 폭 약 300px)
descs=(
  "비공개 위주의 개인 작업 공간입니다."
  "아이디어를 빠르게 시험하는 공간입니다."
  "완료한 작업을 보관하는 공간입니다."
  "참고용으로 포크한 저장소 모음입니다."
)

# GitHub 로고 패스 (simpleicons, 24x24 viewBox)
GH_LOGO='M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12'

FONT='-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif'
W=360    # 카드 폭. metrics(420)보다 좁게 잡아 중간 폭에서 2열 격자 구간(760~820px)을 만든다
CH=76    # 카드 높이 (이름+리포 수 / 설명 / URL 3줄)
PAD=8    # 카드 아래 투명 여백 (세로 스택 시 카드 간격)
PADL=0   # 내부 왼쪽 여백 불필요: GitHub이 img[align=left]에 padding-right 20px를 주입해 그게 거터가 된다
H=$(( CH + PAD ))
TW=$(( W + PADL ))  # 파일 전체 폭

TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

# API 응답에서 정수 필드를 뽑는다 (jq 의존 없이 동작)
json_int() { # $1=json, $2=field
  printf '%s' "$1" | grep -o "\"$2\": *[0-9]*" | head -1 | grep -o '[0-9]*$' || true
}

fetch_counts() { # $1=org -> "공개 N / 비공개 M" 또는 "공개 N" 또는 ""
  local org="$1" json pub priv
  if [ -n "$TOKEN" ]; then
    json=$(curl -sf -H "Authorization: Bearer $TOKEN" "https://api.github.com/orgs/$org" || true)
  else
    json=$(curl -sf "https://api.github.com/orgs/$org" || true)
  fi
  [ -z "$json" ] && { echo ""; return; }
  pub=$(json_int "$json" "public_repos")
  priv=$(json_int "$json" "total_private_repos")
  if [ -n "$priv" ]; then
    echo "공개 ${pub:-0} / 비공개 ${priv}"
  elif [ -n "$pub" ]; then
    echo "공개 ${pub}"
  else
    echo ""
  fi
}

emit_card() { # $1=org, $2=desc, $3=counts
  local org="$1" desc="$2" counts="$3" b64 count_elem=""
  b64=$(curl -sfL "https://github.com/$org.png?size=128" | base64 | tr -d '\n')
  if [ -n "$counts" ]; then
    count_elem="<text class=\"count\" x=\"282\" y=\"27\" text-anchor=\"end\">$counts</text>"
  fi
  cat <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="$TW" height="$H" viewBox="0 0 $TW $H" fill="none">
<style>
.name{font:700 15px $FONT;fill:#24292e}
.desc{font:400 13px $FONT;fill:#586069}
.url{font:400 12px $FONT;fill:#8b949e}
.count{font:400 11px $FONT;fill:#8b949e}
.gh{fill:#8b949e}
.card{fill:#ffffff;fill-opacity:0.55;stroke:#d0d7de;stroke-opacity:1;stroke-width:1}
@media(prefers-color-scheme:dark){.name{fill:#e6edf3}.desc{fill:#adbac7}.url{fill:#8b949e}.count{fill:#8b949e}.gh{fill:#8b949e}.card{fill:#ffffff;fill-opacity:0.08;stroke:#ffffff;stroke-opacity:0.15}}
</style>
<defs><clipPath id="clip"><rect x="294" y="10" width="56" height="56" rx="14" ry="14"/></clipPath></defs>
<g transform="translate($PADL 0)">
<rect class="card" x="0.5" y="0.5" width="$((W-1))" height="$((CH-1))" rx="8"/>
<text class="name" x="20" y="27">$org</text>
<text class="desc" x="20" y="46">$desc</text>
<g transform="translate(20 53) scale(0.5417)"><path class="gh" d="$GH_LOGO"/></g>
<text class="url" x="40" y="64">github.com/$org</text>
$count_elem
<image href="data:image/png;base64,$b64" x="294" y="10" width="56" height="56" clip-path="url(#clip)"/>
</g>
</svg>
SVG
}

# 섹션 제목/캡션 SVG. 일반 텍스트로 두면 README의 플로트 레이아웃에서
# 좁은 폭일 때 한 글자 폭으로 짜부라지므로 이미지로 만든다 (PROJECT.md 참고).
# 높이는 카드와 동일한 H로 맞춘다. 중간 폭에서 플로트가 격자로 타일링될 때
# 행 높이가 어긋나면 지그재그 배치가 되기 때문이다.
# 캔버스 폭 = 카드 플로트 박스 폭(W+20). 헤더는 인라인이라 GitHub 패딩 주입이 없으므로
# 오른쪽 20px를 투명 여백으로 채워 카드와 "metrics 옆에 들어가는 문턱"을 일치시킨다.
# 안 맞추면 특정 폭 구간에서 헤더만 metrics 옆에 붙고 카드는 아래로 떨어져 분리된다.
emit_header() {
  cat <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="$((W+20))" height="$H" viewBox="0 0 $((W+20)) $H" fill="none">
<style>
.h2{font:600 20px $FONT;fill:#24292e}
.cap{font:400 12px $FONT;fill:#586069}
.rule{fill:#d0d7de}
@media(prefers-color-scheme:dark){.h2{fill:#e6edf3}.cap{fill:#adbac7}.rule{fill:#3d444d}}
</style>
<g transform="translate($PADL 0)">
<text class="h2" x="0" y="22">🗂️ 다른 공간의 저장소들</text>
<rect class="rule" x="0" y="32" width="$W" height="1"/>
<text class="cap" x="0" y="56">작업 성격에 따라 저장소를 여러 조직으로 나눠 관리하고 있습니다.</text>
</g>
</svg>
SVG
}

emit_header > org-header.svg
echo "written: org-header.svg"

for i in "${!orgs[@]}"; do
  org="${orgs[$i]}"
  out="org-${shorts[$i]}.svg"
  counts=$(fetch_counts "$org")
  emit_card "$org" "${descs[$i]}" "$counts" > "$out"
  echo "written: $out (${counts:-no counts})"
done
