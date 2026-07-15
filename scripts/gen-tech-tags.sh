#!/usr/bin/env bash
# 기술 태그 SVG(images/tag-*.svg) 생성기 + README 동기화.
# - 아래 tags 배열이 단일 소스다. 태그 변경 = 배열 수정 + 이 스크립트 실행으로 끝난다.
# - 아이콘은 images/icons/<slug>.svg 캐시에서 읽고, 없으면 소스 URL에서 1회 내려받아 검증 후 저장한다.
# - 아이콘 벡터를 태그 SVG 안에 인라인한다(<img> 임베드 SVG는 외부 리소스를 못 불러온다).
# - README.md의 tech-tags 마커 구간을 재생성하고, 배열에 없는 tag-*.svg는 삭제한다.
# - 팔레트는 org 카드와 동일한 테마 중립 모노톤이다(Safari <img> SVG 미디어 쿼리 미지원).
# 설계 배경: docs/superpowers/specs/2026-07-15-tech-tags-design.md, PROJECT.md 참고.
set -euo pipefail

# 저장소 루트에서 실행해도, scripts/에서 실행해도 동작하도록 출력 위치를 고정한다
cd "$(dirname "$0")/.."

# ---- 태그 선언 (단일 소스) ------------------------------------------------
# 형식: "표시이름|slug|소스URL" (1~3필드)
#   1필드: 아이콘 없는 텍스트 필
#   2필드: images/icons/<slug>.svg가 이미 있어야 한다 (직접 넣은 아이콘)
#   3필드: 캐시에 없으면 URL에서 받아 images/icons/<slug>.svg로 저장한다
# 제약: 표시이름은 ASCII(영숫자, # + . / - 공백)만, slug는 ^[a-z0-9][a-z0-9-]*$.
#       URL이 있으면 slug 필수. 다색/스타일 기반/외부 참조 아이콘은 검증에서 거부된다.
DEVICON="https://raw.githubusercontent.com/devicons/devicon/master/icons"
tags=(
  "C#|csharp|$DEVICON/csharp/csharp-plain.svg"
  "C/C++|cplusplus|$DEVICON/cplusplus/cplusplus-plain.svg"
  ".NET|dotnet|$DEVICON/dot-net/dot-net-plain.svg"
  "Unity|unity|$DEVICON/unity/unity-plain.svg"
  "Python|python|$DEVICON/python/python-plain.svg"
  "TypeScript|typescript|$DEVICON/typescript/typescript-plain.svg"
  "PostgreSQL|postgresql|$DEVICON/postgresql/postgresql-plain.svg"
  "Docker|docker|$DEVICON/docker/docker-plain.svg"
  "Synology|synology"  # 공식 로고가 워드마크뿐이라 직접 그린 NAS 픽토그램을 쓴다 (icons/synology.svg, 자체 제작)
  "Git|git|$DEVICON/git/git-plain.svg"
  "GitHub|github|$DEVICON/github/github-original.svg"
  "Visual Studio|visualstudio|$DEVICON/visualstudio/visualstudio-plain.svg"
  "VS Code|vscode|$DEVICON/vscode/vscode-plain.svg"
  "Notion|notion|$DEVICON/notion/notion-plain.svg"
  "JavaScript|javascript|$DEVICON/javascript/javascript-plain.svg"
  "Next.js|nextjs|$DEVICON/nextjs/nextjs-plain.svg"
  "React|react|$DEVICON/react/react-original.svg"
  "Node.js|nodejs|$DEVICON/nodejs/nodejs-plain.svg"
)

# ---- 디자인 상수 -----------------------------------------------------------
FONT='-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif'
INK='#7d8590'   # 글자/아이콘 색 (org 카드 .desc와 동일)
EDGE='#8b949e'  # 필 배경/테두리 색 (org 카드 .card와 동일)
PH=24           # 필 높이 (스타디움: rx = PH/2)
ICON=14         # 아이콘 변 길이
PADL_ICON=10    # 아이콘 있는 필의 좌 패딩
GAP=6           # 아이콘-글자 간격
PADR=12         # 우 패딩
PADL_TEXT=12    # 아이콘 없는 필의 좌 패딩
MR=2            # 캔버스 우측 투명 여백 (README 어절 공백과 합쳐 태그 간격이 된다)
MB=6            # 캔버스 하단 투명 여백 (줄바꿈 시 세로 간격)
H=$((PH + MB))  # 캔버스 높이
BASELINE="16.3" # 12px 글자를 필 세로 중앙에 놓는 baseline (목업 실측으로 보정)

OUT_DIR="images"        # 태그 SVG 산출물 폴더
ICON_DIR="images/icons" # 아이콘 원본 캐시 폴더
README="README.md"
MARK_S='<!-- tech-tags:start -->'
MARK_E='<!-- tech-tags:end -->'

die() { echo "error: $*" >&2; exit 1; }

# ---- 표시 이름 폭 근사 (12px, 0.1px 단위 정수) ------------------------------
# 입력 계약이 허용하는 문자 전부가 표에 있어야 한다. 없는 문자는 오류다.
char_w() {
  case "$1" in
    i|j|l|.)                w=32 ;;
    f|t)                    w=40 ;;
    r|/)                    w=45 ;;
    s)                      w=52 ;;
    c|k|v|x|y|z)            w=57 ;;
    m)                      w=100 ;;
    w)                      w=88 ;;
    a|b|d|e|g|h|n|o|p|q|u)  w=65 ;;
    I)                      w=34 ;;
    J)                      w=48 ;;
    M)                      w=104 ;;
    W)                      w=110 ;;
    E|F|L)                  w=62 ;;
    B|K|P|R|S|T|X|Y|Z)      w=70 ;;
    A|C|D|G|H|N|O|Q|U|V)    w=80 ;;
    [0-9])                  w=67 ;;
    '#')                    w=80 ;;
    '+')                    w=84 ;;
    '-')                    w=48 ;;
    ' ')                    w=37 ;;
    *) die "문자폭 표에 없는 문자: '$1'" ;;
  esac
  echo "$w"
}

label_w_px() { # 표시 이름 -> 폭(px, 반올림 정수)
  local s="$1" total=0 i c
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:$i:1}"
    total=$((total + $(char_w "$c")))
  done
  echo $(((total + 5) / 10))
}

# ---- 아이콘 검증 -----------------------------------------------------------
# 통과 조건: 문서 루트가 <svg>, viewBox 4값 유효(w/h 양수), 외부 참조 없음,
#            <style>/class/인라인 style 없음, none 제외한 paint 색이 1가지 이하.
# 실패 시 이유를 출력하고 1을 반환한다.
# 아이콘 XML을 한 줄로 평탄화한다. CR은 공백이 아니라 삭제해야 한다.
# 공백으로 바꾸면 같은 파일이라도 체크아웃 줄바꿈 상태(LF/CRLF)에 따라
# 출력 공백 수가 달라져 재생성 멱등성이 깨진다 (autocrlf 재체크아웃에서 실측).
xml_flat() { tr -d '\r' < "$1" | tr '\n\t' '  '; }

validate_icon() { # $1=파일
  local flat s vb colors ncolors
  flat=$(xml_flat "$1")

  # 문서 루트 판정: XML 선언/DOCTYPE/주석을 걷어낸 첫 요소가 <svg>여야 한다.
  # "<svg 문자열 포함" 검사는 SVG가 박힌 HTML 페이지도 통과하므로 문서 단위로 본다.
  s="$flat"
  while true; do
    s="${s#"${s%%[![:space:]]*}"}"
    case "$s" in
      '<?'*)   s="${s#*\?>}" ;;
      '<!--'*) s="${s#*-->}" ;;
      '<!'*)   s="${s#*>}" ;;
      *) break ;;
    esac
  done
  case "$s" in
    '<svg'*) : ;;
    *) echo "문서 루트가 <svg>가 아니다"; return 1 ;;
  esac

  vb=$(printf '%s' "$flat" | grep -oE 'viewBox="[^"]*"' | head -1 | sed -E 's/^viewBox="//; s/"$//')
  [ -n "$vb" ] || { echo "viewBox가 없다"; return 1; }
  printf '%s' "$vb" | awk '{
    if (NF != 4) exit 1
    for (i = 1; i <= 4; i++) if ($i + 0 != $i) exit 1
    if ($3 <= 0 || $4 <= 0) exit 1
  }' || { echo "viewBox 값이 유효하지 않다: $vb"; return 1; }

  # 외부 리소스 참조: <img> 임베드에서 로드되지 않아 아이콘이 비거나 일부만 그려진다.
  if printf '%s' "$flat" | grep -qEi '(xlink:href|href)[[:space:]]*=[[:space:]]*["'"'"'](https?:|//)'; then
    echo "외부 href 참조가 있다"; return 1
  fi
  if printf '%s' "$flat" | grep -qEi 'url\([[:space:]]*["'"'"']?(https?:|//)'; then
    echo "외부 url() 참조가 있다"; return 1
  fi

  # 스타일 기반 색 지정은 속성 치환이 닿지 않아 모노톤 보장이 깨진다.
  printf '%s' "$flat" | grep -q '<style' && { echo "<style> 블록이 있다"; return 1; }
  printf '%s' "$flat" | grep -qE 'class[[:space:]]*=' && { echo "class 속성이 있다"; return 1; }
  printf '%s' "$flat" | grep -qE '[[:space:]]style[[:space:]]*=' && { echo "인라인 style 속성이 있다"; return 1; }

  # 다색 검출: 레이어를 한 색으로 칠하면 내부 문양이 사라진 실루엣만 남는다.
  colors=$(printf '%s' "$flat" | grep -oE '(fill|stroke)="[^"]*"' \
    | sed -E 's/^(fill|stroke)="//; s/"$//' | grep -vi '^none$' | sort -u || true)
  ncolors=$(printf '%s' "$colors" | grep -c . || true)
  if [ "$ncolors" -gt 1 ]; then
    echo "paint 색이 2가지 이상이다(다색 아이콘): $(printf '%s' "$colors" | tr '\n' ' ')"; return 1
  fi
  return 0
}

fetch_icon() { # $1=slug, $2=url -> $ICON_DIR/<slug>.svg
  local slug="$1" url="$2" tmp reason
  tmp="$ICON_DIR/.download-$slug.$$"
  curl -sfL --max-time 30 -o "$tmp" "$url" || { rm -f "$tmp"; die "다운로드 실패: $url"; }
  if ! reason=$(validate_icon "$tmp"); then
    rm -f "$tmp"
    die "받은 아이콘이 유효하지 않다($slug): $reason ($url)"
  fi
  mv "$tmp" "$ICON_DIR/$slug.svg"   # 같은 디렉터리 안 이동이라 반쯤 쓴 파일이 남지 않는다
  echo "fetched: $ICON_DIR/$slug.svg"
}

# ---- 아이콘 인라인 (paint 정규화 + viewBox 변환) ----------------------------
# stdout: 태그 SVG에 넣을 <g ...>...</g> 조각
inline_icon() { # $1=slug
  local file="$ICON_DIR/$1.svg" flat roottag inner root_fill root_stroke g_paint
  local vb minx miny vbw vbh tx ty sc
  flat=$(xml_flat "$file")
  roottag=$(printf '%s' "$flat" | grep -oE '<svg[^>]*>' | head -1)
  inner="${flat#*"$roottag"}"
  inner="${inner%</svg>*}"

  # 루트 <svg>의 fill/stroke는 내부 요소만 추출하면 사라지므로 래퍼 <g>로 옮긴다.
  # (예: <svg fill="none" stroke="currentColor">인 윤곽선 아이콘)
  root_fill=$(printf '%s' "$roottag" | grep -oE 'fill="[^"]*"' | head -1 | sed -E 's/^fill="//; s/"$//' || true)
  root_stroke=$(printf '%s' "$roottag" | grep -oE 'stroke="[^"]*"' | head -1 | sed -E 's/^stroke="//; s/"$//' || true)
  if [ "$root_fill" = "none" ]; then g_paint='fill="none"'; else g_paint="fill=\"$INK\""; fi
  if [ -n "$root_stroke" ]; then
    if [ "$root_stroke" = "none" ]; then g_paint="$g_paint stroke=\"none\""
    else g_paint="$g_paint stroke=\"$INK\""; fi
  fi

  # 내부 paint 정규화: none은 보존하고(투명 영역 유지) 나머지 색만 INK로 치환한다.
  # 일반 치환의 값 패턴은 ~로 시작하지 않는 값만 잡는다. [^"]*로 잡으면
  # 보호 마커(~NONE~)까지 다시 매칭되어 none 보존이 무력화되기 때문이다.
  inner=$(printf '%s' "$inner" | sed -E '
    s/(fill|stroke)="[Nn][Oo][Nn][Ee]"/\1="~NONE~"/g
    s/fill="[^~"][^"]*"/fill="'"$INK"'"/g
    s/stroke="[^~"][^"]*"/stroke="'"$INK"'"/g
    s/(fill|stroke)="~NONE~"/\1="none"/g')

  # viewBox(min-x min-y w h) -> 14x14 영역에 균일 스케일 + 중앙 정렬
  vb=$(printf '%s' "$flat" | grep -oE 'viewBox="[^"]*"' | head -1 | sed -E 's/^viewBox="//; s/"$//')
  read -r minx miny vbw vbh <<< "$vb"
  read -r tx ty sc <<< "$(awk -v minx="$minx" -v miny="$miny" -v w="$vbw" -v h="$vbh" \
    -v box="$ICON" -v px="$PADL_ICON" -v py="$(((PH - ICON) / 2))" 'BEGIN {
      s = box / (w > h ? w : h)
      printf "%.4f %.4f %.5f", px + (box - w*s)/2 - minx*s, py + (box - h*s)/2 - miny*s, s
    }')"
  printf '<g transform="translate(%s %s) scale(%s)" %s>%s</g>' "$tx" "$ty" "$sc" "$g_paint" "$inner"
}

# ---- 태그 SVG 한 장 --------------------------------------------------------
emit_tag() { # $1=표시이름, $2=slug(없으면 빈 문자열) -> stdout
  local name="$1" slug="$2" tw pw text_x icon_g=""
  tw=$(label_w_px "$name")
  if [ -n "$slug" ]; then
    pw=$((PADL_ICON + ICON + GAP + tw + PADR))
    text_x=$((PADL_ICON + ICON + GAP))
    icon_g=$(inline_icon "$slug")
  else
    pw=$((PADL_TEXT + tw + PADR))
    text_x=$PADL_TEXT
  fi
  cat <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="$((pw + MR))" height="$H" viewBox="0 0 $((pw + MR)) $H" fill="none">
<style>.t{font:400 12px $FONT;fill:$INK}.p{fill:$EDGE;fill-opacity:0.07;stroke:$EDGE;stroke-opacity:0.4;stroke-width:1}</style>
<rect class="p" x="0.5" y="0.5" width="$((pw - 1))" height="$((PH - 1))" rx="$(awk -v h=$PH 'BEGIN{printf "%.1f", (h-1)/2}')"/>
$icon_g<text class="t" x="$text_x" y="$BASELINE">$name</text>
</svg>
SVG
}

# ---- 1) 입력 검증 (쓰기 전에 전부 확인해 실패를 앞당긴다) --------------------
name_re='^[A-Za-z0-9#+./ -]+$'
slug_re='^[a-z0-9][a-z0-9-]*$'
names=() slugs=() urls=() outs=()
seen_paths=" "
for entry in "${tags[@]}"; do
  IFS='|' read -r name slug url <<< "$entry"
  [ -n "$name" ] || die "표시 이름이 빈 항목이 있다: '$entry'"
  [[ "$name" =~ $name_re ]] || die "표시 이름에 허용 밖 문자가 있다: '$name' (ASCII 영숫자, # + . / - 공백만)"
  if [ -n "$url" ] && [ -z "$slug" ]; then
    die "URL이 있으면 slug가 필수다: '$entry'"
  fi
  if [ -n "$slug" ]; then
    [[ "$slug" =~ $slug_re ]] || die "slug 형식 위반: '$slug' (^[a-z0-9][a-z0-9-]*$)"
    out="tag-$slug.svg"
  else
    norm=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
    [ -n "$norm" ] || die "표시 이름에서 파일명을 만들 수 없다: '$name' (slug를 지정하라)"
    out="tag-$norm.svg"
  fi
  case "$seen_paths" in
    *" $out "*) die "산출물 경로가 겹친다: $out" ;;
  esac
  seen_paths="$seen_paths$out "
  names+=("$name"); slugs+=("$slug"); urls+=("$url"); outs+=("$out")
done

# ---- 2) README 마커 검증 (치환 전에 정확히 한 쌍인지 확인) -------------------
[ -f "$README" ] || die "$README가 없다"
start_ln=$(awk -v m="$MARK_S" '{ sub(/\r$/, "") } $0 == m { print NR }' "$README")
end_ln=$(awk -v m="$MARK_E" '{ sub(/\r$/, "") } $0 == m { print NR }' "$README")
[ "$(printf '%s\n' "$start_ln" | grep -c .)" = 1 ] || die "README 시작 마커가 정확히 1개가 아니다: '$MARK_S'"
[ "$(printf '%s\n' "$end_ln" | grep -c .)" = 1 ] || die "README 종료 마커가 정확히 1개가 아니다: '$MARK_E'"
[ "$start_ln" -lt "$end_ln" ] || die "README 마커 순서가 뒤집혀 있다"

# ---- 3) 아이콘 캐시 확보 (다운로드는 검증 통과 후에만 캐시에 들어간다) --------
mkdir -p "$ICON_DIR"
for i in "${!names[@]}"; do
  slug="${slugs[$i]}"; url="${urls[$i]}"
  [ -n "$slug" ] || continue
  if [ -f "$ICON_DIR/$slug.svg" ]; then
    if reason=$(validate_icon "$ICON_DIR/$slug.svg"); then
      continue
    fi
    if [ -n "$url" ]; then
      echo "cache invalid ($slug): $reason -> 재다운로드"
      rm -f "$ICON_DIR/$slug.svg"
      fetch_icon "$slug" "$url"
    else
      die "캐시된 아이콘이 유효하지 않고 재다운로드할 URL도 없다($slug): $reason"
    fi
  else
    [ -n "$url" ] || die "$ICON_DIR/$slug.svg가 없고 URL도 없다"
    fetch_icon "$slug" "$url"
  fi
done
if ! ls "$ICON_DIR"/LICENSE-* >/dev/null 2>&1; then
  echo "warning: $ICON_DIR/에 제3자 라이선스 고지 파일(LICENSE-*)이 없다. 원본 커밋 시 함께 둔다." >&2
fi

# ---- 4) 태그 SVG 생성 -------------------------------------------------------
for i in "${!names[@]}"; do
  emit_tag "${names[$i]}" "${slugs[$i]}" > "$OUT_DIR/${outs[$i]}"
  echo "written: $OUT_DIR/${outs[$i]} (${names[$i]})"
done

# ---- 5) 배열에 없는 스테일 산출물 삭제 (tag- 접두사는 이 생성기의 예약 공간) --
shopt -s nullglob
for f in "$OUT_DIR"/tag-*.svg; do
  case "$seen_paths" in
    *" ${f#"$OUT_DIR"/} "*) : ;;
    *) rm -f "$f"; echo "removed stale: $f" ;;
  esac
done
shopt -u nullglob

# ---- 6) README 마커 구간 재생성 ---------------------------------------------
# img들을 <div>로 감싼다. 최상위에 img 줄을 나열하면 GitHub 렌더러가 줄마다
# 별도 <p> 문단으로 분리해 태그가 세로로 쌓인다. <div>가 HTML 블록을 열면
# 내용이 원시 HTML로 통과돼 인라인으로 흐른다 (GitHub markdown API로 검증).
block=$(mktemp)
printf '<div>\n' > "$block"
for i in "${!names[@]}"; do
  printf '<img src="./%s/%s" alt="%s" />\n' "$OUT_DIR" "${outs[$i]}" "${names[$i]}" >> "$block"
done
printf '</div>\n' >> "$block"
tmp_readme=$(mktemp)
awk -v s="$MARK_S" -v e="$MARK_E" -v blockfile="$block" '
  { sub(/\r$/, "") }
  $0 == s { print; while ((getline line < blockfile) > 0) print line; inside = 1; next }
  $0 == e { inside = 0 }
  !inside { print }
' "$README" > "$tmp_readme"
mv "$tmp_readme" "$README"
rm -f "$block"
echo "synced: $README (${#names[@]} tags)"
