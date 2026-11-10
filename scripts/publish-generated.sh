#!/usr/bin/env bash
# generated/의 생성 이미지를 output 브랜치에 부모 없는 커밋 하나로 발행한다.
# - main에 커밋하지 않으려고 둔 스크립트다. 생성물을 main에 커밋하면 실행마다 봇 커밋이 쌓여
#   사람이 한 커밋이 git log에 묻히고 로컬 main이 원격보다 늘 뒤처진다.
# - 발행할 때마다 output 브랜치가 generated/ 내용으로 통째로 교체된다. 이전 커밋을 부모로
#   삼지 않으므로 브랜치에는 항상 최신 커밋 하나만 남는다.
# - 커밋 작성자는 실행한 쪽의 git 신원이다. CI에서는 워크플로가 봇 신원을 먼저 설정한다.
# 방법을 고른 근거와 다른 방법의 전제는 docs/ci-auto-commit-history.md 참고.
set -euo pipefail

cd "$(dirname "$0")/.."

SRC=generated   # scripts/gen-org-cards.sh가 출력하는 폴더와 같아야 한다
BRANCH=output

# README가 output 브랜치에서 참조하는 파일이 하나라도 없으면 발행하지 않는다.
# 브랜치가 통째로 교체되므로, 생성 스텝 하나가 빠진 채 발행하면 그 이미지가 프로필에서 깨진다.
refs=$(grep -o "raw\.githubusercontent\.com/[^\"]*/$BRANCH/[^\"]*" README.md | sed "s|.*/$BRANCH/||" | sort -u)
[ -n "$refs" ] || { echo "::error::README.md에 $BRANCH 브랜치 참조가 없다"; exit 1; }
missing=0
for f in $refs; do
  [ -s "$SRC/$f" ] || { echo "::error::README.md가 참조하는 $SRC/$f 가 없다"; missing=1; }
done
[ "$missing" -eq 0 ] || exit 1

# 임시 인덱스로 generated/ 내용만 담은 트리를 만든다. 체크아웃한 워크트리와 main의 인덱스는 그대로 둔다.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tree=$(GIT_INDEX_FILE="$tmp/index" git --work-tree="$SRC" add -A && GIT_INDEX_FILE="$tmp/index" git write-tree)

# 원격의 내용과 같으면 발행하지 않는다. 브랜치가 아직 없으면 fetch가 실패하고 그대로 발행으로 넘어간다.
if git fetch -q --depth 1 origin "$BRANCH" 2>/dev/null; then
  if [ "$(git rev-parse 'FETCH_HEAD^{tree}')" = "$tree" ]; then
    echo "no changes"
    exit 0
  fi
fi

commit=$(git commit-tree "$tree" -m "Update generated images")
git push -q --force origin "$commit:refs/heads/$BRANCH"
echo "published: $BRANCH -> $commit"
