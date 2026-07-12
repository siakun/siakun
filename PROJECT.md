# PROJECT.md

`siakun/siakun` 프로필 저장소의 구성과 결정 근거를 정리한 참고 문서다. 세션 기억이 사라져도 이 문서만으로 현재 상태를 이해하고 재현할 수 있도록 자기완결적으로 적는다.

## 1. 저장소 구성 요약

| 파일 | 역할 | 생성 방식 |
|------|------|-----------|
| `README.md` | 프로필 대문 | 직접 편집 (방문자 대상이라 존댓말 유지) |
| `github-metrics.svg` | GitHub 활동 요약 이미지 | `lowlighter/metrics`가 CI에서 자동 생성 |
| `org-private.svg` 외 `org-*.svg` 4개 | 조직별 북마크 카드 | 직접 생성한 SVG (다크/라이트 테마 대응) |
| `.github/workflows/metrics.yml` | metrics 자동 생성 워크플로 | 직접 편집 |

`org-*.svg`는 조직 아바타를 base64로 내장한 정적 SVG로, 조직당 1파일이다. `@media (prefers-color-scheme: dark)`로 라이트/다크 팔레트를 함께 넣어, 방문자 테마에 따라 자동으로 바뀐다. `<img>` 임베드에서는 SVG 내부 링크가 동작하지 않으므로, 카드를 조직당 1파일로 분리하고 README에서 각 `<img>`를 `<a href>`로 감싸 클릭 이동을 구현한다. 카드 하단에 투명 여백 8px를 넣어 세로 스택 시 카드 간격이 생기게 했다.

## 2. metrics 구성 개요 (metrics.yml)

- **`base: header`만 사용한다.** `activity`, `community`, `repositories` 섹션은 약점 지표(0 PR reviewed, 적은 stars/forks, sponsoring 0 등)를 노출하므로 제외한다. 강점은 아래 플러그인으로 따로 살린다.
- **plugins**
  - `plugin_isocalendar` (half-year): 입체 커밋 캘린더. 꾸준한 실행력을 약점 노출 없이 시각화한다.
  - `plugin_lines`: 코드 작성량. 구현 중심 역량 시그널.
  - `plugin_languages`: 사용 언어 분포. 직무 적합성(C# 최다)을 보여주는 핵심 자산이다.
- **트리거**: 매일 00:00 UTC 스케줄, `workflow_dispatch` 수동 실행, main push.
- **주의**: metrics 액션은 push마다 돌며 `github-metrics.svg`를 origin에 자동 커밋한다. 그래서 로컬과 origin이 자주 발산한다. 푸시 전에 `git pull --rebase origin main`으로 원격의 자동 커밋을 먼저 당긴다.

## 3. lowlighter/metrics 저장소 필터링 메커니즘

출처: `source/app/metrics/utils.mjs`의 `filters.repo()` 함수.
(원문: https://raw.githubusercontent.com/lowlighter/metrics/master/source/app/metrics/utils.mjs )

### 3.1 블랙리스트 (기본 동작, 정확 일치)

- `plugin_languages_skipped`는 전역 `repositories_skipped`를 상속한다.
- 기본 모드에서는 `owner/repo` 문자열이 **정확히 일치**하는 항목만 제외한다. 와일드카드 확장이 없다.
- 매칭 로직(요지): 패턴 배열에 `repo` 이름 또는 `owner/repo` 핸들이 들어 있으면 제외한다.

### 3.2 글로브 패턴 모드 (@use.patterns)

- skip 목록의 **첫 줄에 `@use.patterns`**를 넣으면 `minimatch` 기반 글로브 매칭이 켜진다.
- 이때 `siakun-testing/*` 같은 조직 단위 패턴이 동작한다.
- 매칭 로직(요지): `patterns[0] === "@use.patterns"`이면 각 항목을 `minimatch(handle, pattern)`으로 검사한다.

```yaml
plugin_languages_skipped: |-
  @use.patterns        # 반드시 첫 줄이어야 글로브가 켜진다
  siakun-private/*     # 조직 전체 제외
  bit-flo/*
```

### 3.3 화이트리스트는 네이티브로 없다

- languages 플러그인에는 "이 저장소만 포함"하는 include/allow-list 옵션이 **없다.** `plugin_languages_only` 같은 옵션은 존재하지 않는다.
- 특정 저장소를 강제로 **추가**하는 `plugin_languages_indepth_custom`은 있으나, 이건 분석 대상을 넓히는 용도지 좁히는 용도가 아니다. (skip을 무시하고 포함시킨다.)
- **화이트리스트 효과를 내는 방법**: 네이티브 화이트리스트가 없으므로, 조직 와일드카드로 "제외할 조직"을 지정해 사실상 화이트리스트처럼 운영한다.
  - 장점 1: 제외 조직에 새 스크래치 저장소가 생겨도 자동으로 빠진다. 목록을 계속 갱신할 필요가 없다.
  - 장점 2: `siakun-private`을 조직째 제외하면, 비공개 저장소 이름을 이 **공개** 설정 파일에 하나하나 노출하지 않아도 된다.

### 3.4 가시성(공개/비공개) 필터

- 와일드카드는 **이름 기반**이지 가시성 필터가 아니다. `siakun-private/*`는 그 조직을 통째로 빼는 것이지 "비공개라서" 빼는 게 아니다.
- 위치와 무관하게 "비공개 저장소만 전부" 제외하려면 skip 목록으로는 불가능하다. 가장 견고한 방법은 `METRICS_TOKEN`을 **공개 저장소 권한만 있는 토큰**으로 바꾸는 것이다. 그러면 metrics가 애초에 비공개 저장소를 못 보므로 통계가 자동으로 공개 기준이 된다. (토큰 교체는 저장소 Settings > Secrets에서 직접 한다.)

## 4. 현재 제외/포함 정책 (결정 사항)

언어 통계 기준이다. 커밋/기여 캘린더 같은 다른 지표에는 영향이 없다.

| 대상 | 처리 | 이유 |
|------|------|------|
| 모든 fork 저장소 | 제외 | `repositories_forks: no`. 남의 코드가 섞이지 않게 |
| `siakun-private/*` | 제외 | 비공개 조직. 리포 이름을 공개 설정에 나열하지 않도록 조직 단위로 제외 |
| `siakun-forks/*` | 제외 | 포크 모음 (forks: no로도 걸리지만 명시) |
| `bit-flo/*` | 제외 | 남의 조직/계정 협업 저장소 |
| `siakun/notedrop-share`, `siakun/LetterAI` | 제외 | 메인 계정의 데이터/AI 저장소 |
| `siakun-testing/*` | **포함** | 실험이지만 실제 작업물이라 통계에 넣는다 |
| `siakun-archive/*` | **포함** | 완료/보관한 실제 작업물이라 통계에 넣는다 |

집계 대상은 사실상 "메인 `siakun` 공개 저장소 + `siakun-testing` + `siakun-archive`"에서 위 개별 제외분을 뺀 것이다.

### 포함으로 생기는 부작용 (기억해 둘 것)

`siakun-testing`/`siakun-archive`를 포함하면 그 안의 데이터/노트북/학습 저장소도 같이 집계된다. 대표적으로:

- Jupyter Notebook / Python 비중을 올리는 저장소: `finetune`, `ImageColorAnalyzer`, `ArchiveChatAI`, `Prompts`, `Google-AI-Essentials`
- Java를 추가하는 저장소: `java_workspace`, `java-workspace`

C#을 앞세우려는 취지와 반대로 작동할 수 있다. 거슬리면 이 몇 개만 개별 제외(조직 와일드카드 + 소수 예외 하이브리드)한다. 또한 앞으로 `siakun-testing`에 순수 실험/데이터 저장소를 만들면 자동으로 집계에 들어오므로, 통계를 깔끔히 유지하려면 그런 건 개별 제외하거나 `siakun-private`로 옮긴다.

## 5. 언어 통계 필터 옵션

| 옵션 | 값 | 의미 |
|------|-----|------|
| `plugin_languages_categories` | `markup, programming` | 프로그래밍/마크업 언어만. data/prose 타입 제외 |
| `plugin_languages_threshold` | `1%` | 1% 미만 자투리 언어 숨김 |
| `plugin_languages_limit` | `8` | 상위 8개만 표시 |
| `plugin_languages_indepth` | `no` | indepth는 author 커밋 샘플만 세어 단일 언어로 왜곡되므로 미사용 |
| `plugin_languages_details` | `bytes-size, percentage` | 언어 옆에 바이트/비율 표시 |

## 6. 함정과 주의점 (gotchas)

- **블록 스칼라(`|-`) 안의 `#`는 주석이 아니다.** 리터럴 텍스트로 잡혀 패턴이 깨진다. skip 블록 안에는 패턴만 넣고, 설명은 블록 위 YAML 주석으로 둔다.
- **`@use.patterns`는 반드시 첫 줄이어야** 글로브 모드가 켜진다.
- **`plugin_languages_ignored`(언어 이름 지정 제외)는 신뢰할 수 없다.** `jupyter-notebook`을 넣어도 실제로는 제외되지 않아 5.59%로 계속 표시됐다. 그래서 이 옵션은 제거했다. 노트북을 빼려면 옵션이 아니라 해당 저장소를 skip하거나 category로 접근한다.
- **로컬에서 metrics SVG를 렌더할 수 없다.** `METRICS_TOKEN`이 필요하므로 CI에서만 생성된다. 결과 확인은 push하거나 Actions 탭에서 `workflow_dispatch`로 수동 실행한다.

## 7. 이 문서와 공개 범위

이 저장소는 공개이므로 PROJECT.md도 push하면 공개된다. 비공개 저장소 이름은 이 문서에 적지 않는다. (조직 이름 `siakun-private`은 README에 이미 노출되어 있어 무방하나, 그 안의 개별 저장소 이름은 적지 않는다.)
