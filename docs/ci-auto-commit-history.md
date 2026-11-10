# CI 자동 커밋 히스토리 정리: 전용 브랜치 발행과 조건부 amend

<!-- INTENT: 봇 커밋이 쌓이는 문제에서 방법을 고르고, 고른 방법이 요구하는 전제를 판단하게 하는 레퍼런스다. 조건부 amend는 전제 하나만 빠져도 원격 히스토리나 사람 커밋을 잃으므로, 전제마다 빠졌을 때 실험에서 생긴 결과를 근거로 남긴다. 특정 워크플로의 설정 이야기는 "이 저장소에 적용할 때" 절에만 둔다. -->

GitHub Actions 같은 CI가 생성물(통계 이미지, 배지, 데이터 파일)을 주기적으로 기본 브랜치에 커밋하면 아무도 다시 볼 일이 없는 중간 상태가 히스토리에 계속 쌓이고, 로컬 기본 브랜치는 원격보다 늘 뒤처진다. 해결 원리는 두 가지다. 생성물을 URL로 참조할 수 있으면 기본 브랜치에서 분리해 전용 브랜치에 커밋 하나로 덮어쓴다(방법 1). 생성물이 기본 브랜치의 파일 자체여야 하면 직전 커밋이 자기 커밋일 때만 봇이 그 커밋을 amend하고 force push한다(방법 2). 방법 1은 사람이 작업하는 브랜치를 재작성하지 않으므로 적용할 수 있으면 먼저 고른다. 방법 2는 체크아웃 깊이, push 방식, 봇 식별, 사람 쪽 동기화 명령을 함께 맞춰야 하고, 하나라도 어긋나면 원격 히스토리 전체나 사람 커밋을 잃는다.

## 증상과 적용 범위

- 봇 커밋이 실행마다 하나씩 쌓여 `git log`의 대부분을 차지한다.
- 로컬 기본 브랜치가 원격보다 계속 뒤처져, 사람이 커밋하기 전에 매번 원격 커밋을 당겨야 한다.

내용이 바뀌지 않았는데도 커밋이 생긴다면 원인은 히스토리 정책이 아니라 커밋 조건이다. 스테이징한 뒤 `git diff --cached --quiet`로 변경이 없으면 커밋하지 않게 하고, 생성물에 실행 시각처럼 매번 달라지는 값이 들어가는지부터 확인한다. 이 문서는 내용이 실제로 바뀌지만 중간 상태는 필요 없는 경우를 다룬다.

## 방법을 고르기 전에 확인할 것

1. **생성물을 어디서 참조하는가.** README의 `<img src>`처럼 URL로 참조하는 파일이면 방법 1을 적용할 수 있다. README 본문에 글 목록을 삽입하는 식으로 기본 브랜치의 파일 자체를 수정해야 하면 방법 2만 남는다.
2. **봇이 git 명령으로 커밋하는가.** 워크플로에 `actions/checkout`과 `git commit`이 있으면 커밋 스텝만 교체하면 된다. 액션이 GitHub API로 직접 커밋하면 git 명령이 끼어들 자리가 없다. 커밋을 끄는 출력 옵션으로 파일만 생성하게 하고, 커밋이나 발행은 다음 스텝에서 직접 한다.
3. **같은 신원으로 커밋하는 워크플로가 여럿인가.** 액션이 `GITHUB_TOKEN`으로 API 커밋을 만들면 `github-actions[bot]` 신원으로 기록되고, git 명령으로 커밋하는 워크플로도 대개 같은 이름과 이메일을 설정한다. 방법 2에서 작성자만 보고 자기 커밋을 판정하면 다른 워크플로의 커밋을 amend한다.
4. **사람이 기본 브랜치를 어떻게 따라가는가.** fast-forward만 허용하거나 작업 브랜치를 `git rebase main`으로 올리는 절차라면 방법 2가 그 절차를 깨뜨린다(아래 "사람 쪽 동기화" 참고).

## 방법 1: 전용 브랜치에 커밋 하나로 발행

봇은 사람의 작업 브랜치에 커밋하지 않는다. 생성물만 담은 부모 없는(orphan) 커밋을 만들어 전용 브랜치에 force push하므로 그 브랜치에는 항상 최신 커밋 하나만 남는다. 그 브랜치를 작업 기반으로 삼는 사람이 없으니 force push가 누구의 작업도 덮지 않고, 기본 브랜치는 재작성되지 않는다.

이 동작을 제공하는 액션이 이미 있다.

- `peaceiris/actions-gh-pages`: `publish_branch`로 대상 브랜치를 정하고 `force_orphan: true`로 최신 커밋 하나만 남긴다.
- `crazy-max/ghaction-github-pages`: `target_branch`로 대상 브랜치를 정한다. `keep_history` 기본값이 `false`여서 별도 설정 없이 매번 force push한다.

액션 없이 git 명령으로도 같은 발행을 할 수 있다. 워크플로가 이미 저장소를 체크아웃했다면 그 저장소의 `origin`과 인증을 그대로 사용하므로 토큰을 따로 넘기지 않아도 된다.

```bash
# 발행할 폴더($SRC)만 담은 트리를 임시 인덱스로 만든다. 체크아웃한 워크트리와 인덱스는 그대로다
tree=$(GIT_INDEX_FILE="$tmp/index" git --work-tree="$SRC" add -A && GIT_INDEX_FILE="$tmp/index" git write-tree)

# 원격의 트리와 같으면 발행하지 않는다. 브랜치가 아직 없으면 fetch가 실패하고 발행으로 넘어간다
if git fetch -q --depth 1 origin "$BRANCH" 2>/dev/null &&
   [ "$(git rev-parse 'FETCH_HEAD^{tree}')" = "$tree" ]; then
  exit 0
fi

commit=$(git commit-tree "$tree" -m "Update generated files")   # -p를 주지 않아 부모 없는 커밋이 된다
git push --force origin "$commit:refs/heads/$BRANCH"
```

방법 2와 달리 여기서는 `--force`와 깊이 1 체크아웃이 문제가 되지 않는다. 발행할 때마다 생성물 전체를 새로 만들어 브랜치를 교체하므로 덮어써서 잃는 내용이 없고, 새 커밋에 부모가 없으니 로컬에 이전 히스토리가 없어도 된다.

README 같은 문서는 상대 경로 대신 그 브랜치의 raw URL로 생성물을 참조한다.

```
https://raw.githubusercontent.com/<owner>/<repo>/<branch>/<file>
```

한계는 두 가지다.

- 위 설정으로 발행하면 브랜치 내용이 발행한 디렉터리 내용으로 통째로 교체된다. 생성기 여럿이 같은 브랜치에 따로 발행하면 나중에 발행한 쪽이 앞의 파일을 삭제한다. 생성기마다 브랜치를 나누거나, 한 워크플로에서 생성물을 모아 한 번에 발행한다.
- 생성물의 과거 버전이 남지 않는다. 변화 추이를 git 히스토리로 추적해야 하면 이 방법이 맞지 않는다.

통째 교체는 실수 두 가지로 이어지므로 함께 막는다.

- **일부만 생성된 채 발행.** 생성 스텝 하나가 빠지거나 건너뛰어진 상태로 발행하면 그 파일이 브랜치에서 사라지고, 그 파일을 참조하는 문서의 이미지가 깨진다. 발행 전에 문서가 그 브랜치에서 참조하는 파일 목록을 문서에서 직접 읽어 모두 있는지 확인하고, 하나라도 없으면 발행하지 않는다. 목록을 스크립트에 따로 적어 두면 문서와 어긋난다.
- **기본 브랜치에서 방법 1로 전환하는 순서.** 문서가 새 URL을 가리키는 커밋이 발행 브랜치보다 먼저 원격에 올라가면 첫 발행이 끝날 때까지 이미지가 깨지고, 새 워크플로가 실패하면 깨진 채로 남는다. 현재 생성물로 발행 브랜치를 먼저 만들어 두고(또는 같은 push에 함께 올리고) 문서를 전환한다.

## 방법 2: 직전 커밋이 자기 커밋일 때만 amend

브랜치 끝이 자기 봇 커밋이면 그 커밋을 amend하고, 사람 커밋이 끝에 있으면 새 커밋을 만든다. 그러면 기본 브랜치에는 사람 커밋 사이마다 봇 커밋이 많아야 하나만 남는다.

아래 스크립트를 워크플로의 커밋 스텝에서 실행한다. 식별자(`KEY`), 커밋 메시지(`MSG`), 대상 브랜치(`BRANCH`), 커밋할 경로(`PATHS`, 공백으로 구분한 git pathspec)를 환경 변수로 받는다.

```bash
#!/usr/bin/env bash
# 생성물 커밋: 직전 커밋이 같은 봇(같은 KEY)의 커밋이면 amend 후 force-with-lease, 아니면 새 커밋
set -euo pipefail
: "${KEY:?}" "${MSG:?}" "${BRANCH:?}" "${PATHS:?}"
me=$(git config user.email)   # 자기 커밋 판정 기준. 워크플로가 이 스크립트 전에 봇 신원을 설정한다

set -f   # PATHS의 glob은 셸이 아니라 git pathspec이 해석한다(삭제된 파일도 잡힌다)
git add -A -- $PATHS
set +f
git diff --cached --quiet && { echo "no changes"; exit 0; }

base=$(git rev-parse HEAD)
last_key=$(git log -1 --format='%(trailers:key=Bot-Commit,valueonly)')
last_committer=$(git log -1 --format='%ce')

# 사람이 rebase로 다시 만든 커밋은 committer가 바뀌므로 amend 대상에서 빠진다
if [ "$last_key" = "$KEY" ] && [ "$last_committer" = "$me" ]; then
  # depth 1 체크아웃에서는 HEAD의 부모가 안 보여 amend 결과가 루트 커밋이 되고, force push가 전체 히스토리를 지운다
  git rev-parse -q --verify HEAD~1 >/dev/null || { echo "::error::checkout fetch-depth must be >= 2"; exit 1; }
  if git diff --cached --quiet HEAD~1; then
    git reset -q --soft HEAD~1   # 값이 봇 커밋 이전으로 돌아왔으면 봇 커밋 자체를 없앤다
  else
    git commit -q --amend --reset-author -m "$MSG" --trailer "Bot-Commit: $KEY"
  fi
  git push -q --force-with-lease="refs/heads/$BRANCH:$base" origin "HEAD:refs/heads/$BRANCH"
else
  git commit -q -m "$MSG" --trailer "Bot-Commit: $KEY"
  git push -q origin "HEAD:refs/heads/$BRANCH"
fi
```

워크플로에서는 체크아웃 깊이와 봇 신원을 스크립트보다 먼저 설정한다.

```yaml
jobs:
  update:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 2   # 1이면 amend 결과가 루트 커밋이 된다

      # (생성물을 만드는 스텝)

      - name: Commit generated files
        env:
          KEY: org-cards
          MSG: Update org cards
          BRANCH: ${{ github.ref_name }}
          PATHS: images/org-*.svg
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          bash scripts/bot-commit.sh
```

여러 저장소에서 사용하려면 이 스크립트를 composite action으로 감싸 한 저장소에 두고, 각 워크플로에서 `uses:`로 호출한다.

스크립트가 지키는 전제는 네 가지다. 각 전제가 빠졌을 때의 결과는 아래 "검증" 절의 실험에서 확인했다.

### 체크아웃 깊이 2 이상

`actions/checkout`의 `fetch-depth` 기본값은 1이다. 깊이 1인 shallow clone에서 HEAD는 shallow 경계여서 git이 HEAD의 부모를 없는 것으로 다룬다. 이 상태에서 amend하면 새 커밋은 부모가 없는 루트 커밋이 되고, 이 커밋을 force push하면 원격 브랜치의 히스토리 전체가 커밋 하나로 대체된다. 깊이가 2면 HEAD~1이 로컬에 있으므로 amend한 커밋이 원래 부모를 그대로 가리킨다.

스크립트는 amend 직전에 `git rev-parse --verify HEAD~1`로 부모가 보이는지 확인하고, 보이지 않으면 실패로 끝낸다. 워크플로에서 `fetch-depth`를 빠뜨리는 실수를 스크립트가 막게 하려는 장치다.

### 체크아웃 시점 SHA를 명시한 `--force-with-lease`

봇이 체크아웃한 뒤 사람이 push하면, 봇이 `--force`로 push하는 순간 사람 커밋이 원격에서 사라진다. 피해는 원격에서 끝나지 않는다. 사람이 다음에 `git pull --rebase`를 실행하면 git은 원격 추적 브랜치의 reflog로 fork-point를 계산한다. 사람이 push한 커밋이 그 reflog에 들어 있으므로 git은 그 커밋을 원격이 되돌린 커밋으로 판정해 로컬 브랜치에서도 제외한다. 경고 없이 사라지고 reflog로만 복구할 수 있다.

`--force-with-lease=refs/heads/<branch>:<SHA>`는 원격 브랜치 끝이 그 SHA일 때만 덮어쓴다. 사이에 사람이 push했으면 push가 `stale info`로 거부되고 봇의 실행만 실패한다. 다음 실행은 새 끝을 기준으로 다시 처리한다. SHA를 생략한 `--force-with-lease`는 원격 추적 브랜치의 값과 비교하므로, 그 사이에 `git fetch`가 실행되면 비교 기준이 최신값으로 갱신되어 보호가 사라진다(git-push 문서의 경고). 그래서 스크립트는 커밋하기 전의 HEAD를 변수에 담아 명시한다.

### trailer로 판정하는 자기 커밋

스크립트는 커밋 메시지 끝에 `Bot-Commit: <KEY>` trailer를 추가하고, 직전 커밋의 trailer가 같은 KEY일 때만 amend한다. committer 이메일이 현재 설정한 봇 신원과 같은지도 함께 확인한다. 사람이 rebase로 다시 만든 커밋은 committer가 사람으로 바뀌므로 amend 대상에서 빠진다. 여러 워크플로의 커밋을 하나로 합치려면 같은 KEY를 지정한다.

### 값이 되돌아왔을 때의 봇 커밋 제거

새 생성물이 직전 사람 커밋 시점의 내용과 같아지면 amend 결과가 빈 커밋이 되고, `git commit --amend`는 빈 커밋을 거부하며 실패한다. 스크립트는 이 경우 `git reset --soft HEAD~1`로 봇 커밋을 없애고 force push한다.

## 사람 쪽 동기화

방법 2에서는 원격의 봇 커밋이 재작성되므로, 로컬 기본 브랜치가 옛 봇 커밋을 가리키면 원격과 발산한다.

- `git pull --ff-only`는 실패한다.
- `git pull --rebase`는 그대로 사용할 수 있다. fork-point 계산이 옛 봇 커밋을 원격이 재작성한 커밋으로 알아보고, 로컬 커밋만 새 봇 커밋 위로 옮긴다.
- `git rebase origin/main`처럼 upstream을 명령에 적으면 git은 fork-point를 계산하지 않는다. 옛 봇 커밋이 로컬에만 있는 커밋으로 잡혀 새 봇 커밋 위에 다시 적용되고, 두 커밋이 같은 파일의 같은 부분을 수정하므로 충돌한다. 작업 브랜치를 기본 브랜치 위로 올리는 절차에서는 `git rebase --fork-point origin/main`을 사용한다.

fork-point는 reflog에 기댄다. 옛 봇 커밋을 받은 지 오래되어 원격 추적 브랜치의 reflog 항목이 만료되면(현재 끝에서 도달할 수 없는 항목은 `gc.reflogExpireUnreachable` 기본값 30일) 옛 봇 커밋을 알아보지 못하고, upstream을 명시한 rebase와 같은 충돌이 난다. 이 한계는 git 문서에서 도출했고 실험으로 확인하지 않았다. 그때는 `git rebase --onto origin/main <옛 봇 커밋> <작업 브랜치>`로 옛 봇 커밋을 직접 제외한다.

## 이미 쌓인 봇 커밋 걷어내기

위 두 방법은 앞으로 생길 봇 커밋만 줄인다. 이미 쌓인 봇 커밋을 없애려면 기본 브랜치의 히스토리를 다시 작성해 force push해야 한다. 봇 커밋 뒤의 모든 커밋 ID가 바뀌므로 한 번만 하고, 방법 1로 전환한 뒤에 한다. 봇이 기본 브랜치에 커밋하는 동안에는 다시 작성하는 사이에 새 봇 커밋이 원격에 올라온다.

걷어내는 방식은 두 가지이고 남는 히스토리가 다르다.

- **생성물 경로를 히스토리 전체에서 제거한다.** 봇 커밋은 생성물만 수정하므로 내용이 비어 사라지고, 사람 커밋에는 사람이 수정한 파일만 남는다. 기본 브랜치의 끝에 생성물이 더는 없을 때, 곧 방법 1로 전환한 뒤에만 최종 파일 내용이 그대로 유지된다.
- **봇 커밋만 건너뛰고 이후 커밋의 스냅샷은 유지한다.** 과거 커밋의 파일 상태가 그대로 남지만, 봇이 변경한 생성물이 바로 다음 사람 커밋의 diff에 섞여 들어가 그 커밋이 생성물을 수정한 것처럼 보인다. 생성물이 기본 브랜치에 계속 있어야 하는 방법 2에서는 이 방식만 가능하다.

경로 제거는 `git filter-repo`로 한다. 다시 작성하기 전에 세 가지를 확인한다.

1. **제거할 경로의 전체 목록.** 봇 커밋이 수정한 경로에 더해, 같은 생성물이 폴더 이동 전에 있던 경로와 봇은 수정하지 않았지만 같은 생성기가 만드는 파일까지 포함한다. 하나라도 빠지면 그 파일을 수정한 봇 커밋이 남는다.
2. **그 경로만 수정한 사람 커밋이 있는가.** 있으면 그 커밋도 비어서 함께 사라진다.
3. **그 경로에 사람이 직접 작성한 내용이 있었는가.** 생성기를 도입하기 전에 손으로 만든 파일이 같은 경로에 있었다면 그 버전도 히스토리에서 사라진다.

```bash
# 1. 봇이 수정한 경로와, 같은 이름의 파일이 있던 모든 경로
git log --author='github-actions\[bot\]' --name-only --format= | sort -u
git log --name-only --format= | grep -E '<생성물 파일명 패턴>' | sort -u

# 원본 저장소는 그대로 두고 새 복제본에서 다시 작성한다
git clone --no-local --single-branch --branch main <원본 저장소> rewrite && cd rewrite
git filter-repo --invert-paths --preserve-commit-hashes --path <경로1> --path <경로2>
```

`--path`는 glob 대신 경로를 하나씩 적는다. 패턴이 뜻하지 않은 파일까지 제거하는 일을 막으려는 것이다. `--preserve-commit-hashes`는 커밋 메시지 본문에 적힌 커밋 ID를 filter-repo가 새 ID로 바꿔 적지 않게 한다. 비게 된 커밋과, 한쪽 부모가 사라져 머지할 것이 없어진 머지 커밋은 기본 설정에서 함께 제거된다. filter-repo가 복제본에서 `origin`을 삭제하므로 원본 저장소에서 `git fetch <복제본 경로> main:tmp`로 결과를 가져와 대조한 뒤 브랜치를 옮긴다.

옮기기 전에 원본과 대조한다. 옛 ID와 새 ID의 대응은 복제본의 `.git/filter-repo/commit-map`에 있고, 사라진 커밋은 새 ID가 0으로 채워진다.

- 최종 트리가 같다: `git diff --quiet <원본> <결과>`.
- 사라진 커밋이 봇 커밋과 머지할 것이 없어진 머지 커밋뿐이다.
- 남은 커밋마다 원본 트리에서 제거한 경로를 뺀 파일 목록이 결과 트리와 같고, 작성자, 커미터, 두 날짜, 메시지가 같다.

push는 다시 작성하기 전에 확인한 원격 끝을 명시한 lease로 한다. 그 사이 원격에 올라온 커밋이 있으면 거부되므로, 올라온 커밋을 확인한 뒤 다시 작성한다.

```bash
git push --force-with-lease=main:<다시 작성하기 전의 원격 SHA> origin main
```

다시 작성해도 사라지지 않는 것이 있다. 옛 커밋을 포함한 다른 원격 브랜치나 태그가 있으면 옛 히스토리가 원격에 계속 남으므로 그 ref도 정리한다. 서명된 커밋은 ID가 바뀌면서 서명을 잃는다.

## 권하지 않는 방법

- **`stefanzweifel/git-auto-commit-action`의 amend 레시피를 그대로 사용하기.** README의 "Using `--amend` and `--no-edit` as commit options" 절은 `fetch-depth: 2`, `commit_options: '--amend --no-edit'`, `push_options: '--force'`, `skip_fetch: true` 조합을 제시한다. 깊이 조건은 맞지만 직전 커밋이 누구의 것이든 amend하므로, 사람 커밋이 끝에 있으면 그 커밋에 봇 변경이 섞이고 SHA가 달라진다. push도 `--force`여서 위 경쟁 상황에서 사람 커밋을 지운다. 앞 스텝에서 직전 커밋을 판정해 `if:`로 호출을 나누고 `push_options`에 SHA를 명시한 lease를 전달하면 같은 안전성을 얻지만, 그만큼 조립할 바에는 git 명령으로 직접 작성하는 편이 읽기 쉽다.
- **봇 커밋을 주기적으로 몰아서 squash하는 별도 작업.** 재작성 범위가 브랜치 끝의 커밋 하나에서 여러 커밋으로 넓어지고, 그 구간 사이에 사람 커밋이 있으면 사람 커밋의 SHA까지 모두 달라진다. 구조에서 도출한 한계이며 실험하지 않았다.

## 검증

bare 저장소를 원격으로 두고 사람 clone과 봇 clone을 번갈아 조작해 확인했다(Git 2.47). 봇 clone은 `file://` URL로 만든다. 로컬 경로로 clone하면 `--depth`가 무시되어 shallow 조건을 재현할 수 없다. `git commit --trailer`는 Git 2.32 이상이 필요하다.

방법 1의 git 명령 발행은 참조 파일 확인을 앞에 추가한 스크립트로 확인했다.

| 조건 | 결과 |
|---|---|
| 발행 브랜치가 아직 없음 | 브랜치 생성, 커밋 1개, 부모 0개 |
| 생성물 변화 없음 | 발행 생략 |
| 생성물 내용 변경 | 브랜치 끝이 새 커밋으로 교체, 커밋 수는 그대로 1개 |
| 발행 폴더에서 파일 하나를 삭제하고 발행 | 브랜치에서도 그 파일이 사라짐 |
| 문서가 참조하는 파일이 발행 폴더에 없음 | 확인 단계에서 실패로 종료, 원격 변화 없음 |
| 깊이 1 체크아웃에서 발행 | 정상 발행, 기본 브랜치 히스토리 변화 없음 |
| 발행 전후의 체크아웃 상태 | HEAD, 인덱스, 워크트리 모두 그대로 |

방법 2의 스크립트는 아래와 같이 동작했다.

| 조건 | 결과 |
|---|---|
| 사람 커밋이 끝에 있음 | 새 봇 커밋 |
| 같은 KEY의 봇 커밋이 끝에 있음 | amend, 부모는 직전 사람 커밋 그대로 |
| 생성물 변화 없음 | 커밋과 push 모두 생략 |
| 값이 직전 사람 커밋 시점으로 복귀 | 봇 커밋 제거 |
| 다른 KEY의 봇 커밋이 끝에 있음 | 새 봇 커밋 |
| `PATHS` glob 대상 파일 삭제 | 삭제까지 커밋에 포함 |
| 깊이 1, 스크립트 실행 | 가드가 실패로 종료, 원격 변화 없음 |
| 깊이 1, 가드 없이 amend 후 `--force` | 새 커밋의 부모 0개, 원격 히스토리가 커밋 하나로 대체됨 |
| 체크아웃 뒤 사람이 push, 스크립트의 lease push | `stale info`로 거부, 사람 커밋 보존 |
| 같은 경쟁, `--force` | 사람 커밋이 원격에서 사라지고, 사람이 `pull --rebase`한 뒤 로컬에서도 사라짐 |
| 사람의 미푸시 커밋이 옛 봇 커밋 위에 있음 | `pull --rebase` 성공, `rebase origin/main` 충돌, `rebase --fork-point origin/main` 성공 |

생성물 경로 제거는 봇 커밋이 대부분이고 머지 커밋이 하나 있는 히스토리에서 확인했다. 그 머지 커밋은 한쪽 부모 쪽에 봇 커밋만 있었다.

| 확인한 것 | 결과 |
|---|---|
| 최종 트리 | 원본과 동일 |
| 봇 커밋 | 모두 제거 |
| 한쪽에 봇 커밋만 있던 머지 커밋 | 제거되어 히스토리가 한 줄이 됨 |
| 사람 커밋의 수 | 원본과 동일 (제거한 경로만 수정한 사람 커밋이 없었음) |
| 사람 커밋의 트리 | 원본 트리에서 제거한 경로를 뺀 것과 동일 |
| 사람 커밋의 작성자, 커미터, 날짜, 메시지 | 원본과 동일 |
| 사람 커밋의 patch-id | 원본 diff에서 제거한 경로를 뺀 것과 동일 |
| 첫 생성물 커밋보다 앞선 커밋의 ID | 그대로 |

머지 커밋의 양쪽에 모두 사람 커밋이 있는 히스토리와 서명된 커밋이 있는 히스토리는 확인하지 않았다.

가장 놓치기 쉬운 두 결과는 아래 순서로 재현한다.

```bash
# 깊이 1에서 amend하면 루트 커밋이 된다
git clone --depth 1 file:///path/to/remote.git bot && cd bot
echo x > data.txt && git commit -qa --amend --no-edit
git cat-file -p HEAD | grep -c '^parent'    # 0

# --force가 덮은 사람 커밋은 pull --rebase 뒤 로컬에서도 사라진다 (원격 끝이 봇 커밋인 상태에서 시작)
git clone --depth 2 file:///path/to/remote.git bot    # 봇 체크아웃
# 사람 clone: git pull --rebase 후 커밋 U를 만들어 git push
# 봇 clone:   git commit -qa --amend --no-edit && git push --force origin HEAD:main
# 사람 clone: git pull --rebase && git log --oneline    (U가 없다)
```

운영 중에는 다음을 확인한다.

- `git log --format='%h %s %(trailers:key=Bot-Commit,valueonly)'`에서 같은 KEY의 봇 커밋이 연달아 있으면 판정 조건이 어긋난 것이다.
- lease 거부는 워크플로 실패로 나타난다. 가끔 실패하는 것은 보호가 작동한 결과다. 매번 실패하면 같은 브랜치에 push하는 다른 워크플로가 동시에 도는지 확인하고, 그런 워크플로들을 같은 `concurrency` 그룹으로 묶는다(GitHub Actions 문서의 동작이며 이 실험에서는 확인하지 않았다).

## 이 저장소에 적용할 때

README가 `<img src>`로 참조하는 CI 생성물(metrics 이미지와 조직 카드)에 방법 1을 적용했다. 구성과 운영 규칙은 `PROJECT.md` 1장 "생성 이미지 발행" 절에 있고, 여기에는 방법을 적용하며 내린 판단만 적는다.

- **생성기 둘을 [generated-images.yml](../.github/workflows/generated-images.yml)의 job 하나에 모았다.** 워크플로를 나눠 같은 브랜치에 따로 발행하면 통째 교체 한계에 걸리고, 브랜치를 나누면 관리할 브랜치가 늘어난다. 두 생성물은 README의 한 구간에 함께 쓰이므로 한 번에 발행하는 쪽을 골랐다.
- **`lowlighter/metrics`는 `output_action: none`으로 실행한다.** 기본 설정(`commit`)은 GitHub REST API(`createOrUpdateFileContents`)로 직접 커밋하므로 git 명령이 끼어들 자리가 없다. `none`이면 커밋하지 않고 러너의 `/metrics_renders/<filename>`에 파일만 생성하므로 다음 스텝에서 발행 폴더로 복사한다.
- **발행은 액션 대신 [publish-generated.sh](../scripts/publish-generated.sh)의 git 명령으로 한다.** 발행 전에 README의 참조 파일을 확인하는 단계가 필요했고, 그 확인과 발행을 한 스크립트에 두면 로컬에서 bare 저장소를 상대로 그대로 검증할 수 있다.
- **전환 뒤 생성물 경로를 히스토리에서 제거해 이전 봇 커밋을 걷어냈다.** 그래서 과거 커밋을 체크아웃하면 그 시점의 README가 참조하는 생성 이미지 파일이 없다. 조직 카드는 생성기를 도입하기 전에 손으로 만든 버전이 같은 경로에 있었고 그 버전도 함께 제거됐다. 생성기를 도입한 뒤의 카드 디자인은 `scripts/gen-org-cards.sh`의 히스토리에 남아 있다.
- **액션의 `committer_branch` 옵션으로 발행 브랜치를 지정하는 방법은 고르지 않았다.** 기본 브랜치에서는 봇 커밋이 사라지지만 발행 브랜치에는 실행마다 커밋이 계속 쌓이고, git 명령으로 커밋하는 조직 카드 쪽은 같은 브랜치에 맞춰 따로 처리해야 한다.

## 근거

- git-rebase `--fork-point`: 명령에 upstream을 주면 기본값이 `--no-fork-point`, 생략하면 `--fork-point`다. <https://git-scm.com/docs/git-rebase>
- git-push `--force-with-lease=<refname>:<expect>`와 값을 생략했을 때의 안전성 주의. <https://git-scm.com/docs/git-push>
- git-commit `--reset-author`, `--trailer`. <https://git-scm.com/docs/git-commit>
- pretty format `%(trailers:key=...,valueonly)`. <https://git-scm.com/docs/pretty-formats>
- `gc.reflogExpireUnreachable`. <https://git-scm.com/docs/git-config>
- `actions/checkout`의 `fetch-depth`. <https://github.com/actions/checkout>
- git-auto-commit-action README의 "Using `--amend` and `--no-edit` as commit options". <https://github.com/stefanzweifel/git-auto-commit-action>
- lowlighter/metrics의 `output_action` 정의와 커밋 구현. <https://github.com/lowlighter/metrics/blob/master/source/plugins/core/metadata.yml>, <https://github.com/lowlighter/metrics/blob/master/source/app/action/index.mjs>
- peaceiris/actions-gh-pages의 `force_orphan`. <https://github.com/peaceiris/actions-gh-pages>
- crazy-max/ghaction-github-pages의 `keep_history`. <https://github.com/crazy-max/ghaction-github-pages>
