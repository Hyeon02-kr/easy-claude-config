# TOOLS.md

MCP 서버·스킬·플러그인 개별 사용법·주의사항을 정리한 개인 참고 문서.

**이 문서를 두는 이유**: 스킬(`SKILL.md`)·MCP 서버 자체 설명·플러그인 내용은 제작자가 업데이트할 때마다 덮어써진다. 실제로 써보면서 확인한 제약사항·버그·요령은 여기에만 남는다. `CLAUDE.md`는 "언제 이 도구를 쓸지"에 대한 짧은 트리거 규칙만 담고, "어떻게 쓰는지·뭘 조심해야 하는지"는 이 문서가 담당한다.

**갱신 원칙**: 새 MCP/스킬/플러그인을 설치하거나, 기존 도구에서 새로운 제약·버그·요령을 발견하면 이 문서에 추가한다.

---

## MCP 서버

### context7
- **용도**: 라이브러리·프레임워크·SDK·API·CLI 문서 최신본 조회
- **트리거**: 라이브러리 언급 시 항상 먼저 사용(학습 데이터가 오래됐을 수 있음을 전제)

### tavily
- **용도**: 웹 검색
- **트리거**: 웹 검색이 필요한 모든 상황에서 반드시 사용
- **참고**: 검색어에 연도가 필요하면 현재 날짜부터 확인

### notion
- **용도**: Notion 페이지·데이터베이스 검색·생성·편집, 대화 내용을 지속 가능한 문서로 정리
- **트리거**: 사용자가 다시 찾아보거나 공유·추적·유지할 만한 결과물을 만들 때(notion 서버 자체 안내 참고)
- **연결 방식 (2026-09-10 간접 확인)**: `claude mcp list`는 비밀값 노출 방지 차단 규칙 때문에 직접 실행하지 않았다. 대신 전역 npm 패키지·`~/.claude/bin`·`~/.claude/skills`에 관련 흔적이 전혀 없고 `mcp-secrets.example.json`에도 항목이 없다는 점으로 원격 HTTP+OAuth 서버(tavily와 동일 패턴)라고 판단함 — **[추정]**, `/mcp` 메뉴로 직접 재확인 권장.
- `mcp-servers.json`에 `transport: http`, `url: https://mcp.notion.com/mcp`, `auth: oauth`로 선언함. 새 기계에서는 `/mcp`에서 브라우저 OAuth 인증이 필요(스크립트로 자동화 불가, tavily와 동일).

> **제거됨 (2026-09-10): sequential-thinking.** 이 세션이 이미 `settings.json`의 `alwaysThinkingEnabled: true` + `effortLevel: high`로 네이티브 확장 사고를 쓰고 있어서, 사고 단계를 도구 호출로 흉내 내는 이 MCP의 효용이 사실상 없었다 — 실제로 이전까지의 긴 다단계 작업 전체에서 한 번도 호출되지 않은 것으로 확인됨. 재도입을 고려한다면 먼저 네이티브 사고가 꺼져 있거나 부족한 상황인지부터 확인할 것.

### playwright
- **용도**: 브라우저 자동화, UI 테스트, 스크래핑
- **트리거**: 브라우저 동작 확인·UI 테스트·스크래핑이 필요한 상황
- **특이사항**: 창은 사용자와 공유하는 실브라우저다 — 로그인·캡차·파일 선택처럼 자동화가 막히는 지점은 억지로 우회하지 말고 사용자에게 직접 조작을 요청하고, `browser_snapshot`(접근성 트리)을 기본으로 쓴다(`browser_take_screenshot`은 명시 요청 시에만).

### kordoc (한국어 문서 파싱·생성)
- **용도**: HWP/HWPX/PDF/DOCX/XLSX 등 파싱→마크다운, 마크다운→HWPX 생성, 문서 diff, 렌더(PNG/SVG), 서식 채우기
- **중요 제약 (실측 확인, 2026-08-16~17)**:
  - `generate_document`의 `cover`/`toc`/`org`/`date`/`fonts`/`body_pt`/`sizes` 파라미터는 **`preset` 없이(범용 모드)는 전혀 작동하지 않는다.** `cover:true`를 줘도 XML에 `pageBreak` 자체가 0개, 표지 텍스트도 반영 안 됨 — 직접 XML까지 까서 확인함. `preset`(예: `개조식`, `보고서`)을 주면 작동하지만, 대신 문서 스타일이 공문서/정부 표준 개조식 등으로 강제로 바뀐다(박스 프리픽스 제목 등).
  - **용지 여백(margin) 지정 파라미터가 스키마에 아예 없다.** 여백은 kordoc으로 못 하고 hwpx-skill의 `set-page --margin-mm`로 사후 패치해야 한다.
  - **`patch_document`(기존 문서 텍스트 수정)는 마크다운 서식(백틱 인라인코드, `**`굵게)을 재해석하지 못한다.** 편집 대상 문단에 새로 마크다운 문법을 넣으면 (a) 백틱/별표가 텍스트에 리터럴로 그대로 남거나 (b) 전체 문단이 원래 있던 run의 charPr 하나로 뭉개지고 빈 run이 덕지덕지 붙는 버그가 여러 번 재현됨. **패치할 땐 서식 문자(백틱, `**`) 없이 순수 텍스트만 넣을 것.** 서식이 꼭 필요하면 직접 XML을 열어 run을 수동으로 나눠야 한다.
  - `render_document`는 캐시 없는 AI 생성본에 대해 reflow 근사 렌더러를 쓰므로 **`pageBreak` 속성을 반영하지 않는다**(실제 한글에서는 반영되는 게 정상). 페이지 분리 여부는 렌더로 확인 안 되고, XML의 `pageBreak` 속성을 직접 읽거나 실제 한글/한컴독스에서 열어 확인해야 한다. → **`pageBreak="1"`가 실제 앱(HOP)에서 의도대로 작동하는 것을 사용자가 직접 확인함(2026-08-18)** — hwpx-skill의 `page-break` 명령으로 건 페이지 나눔이 렌더러로는 안 보였지만 실제 앱에서는 정확히 반영됐다. XML 근거만으로도 신뢰해도 되는 기능으로 격상.

### rhwp (edwardkim/rhwp, 오픈소스 Rust HWP 뷰어)
- **용도**: HWP/HWPX/HML 렌더링(SVG/PNG), 문서 구조·개요 추출, 표/필드 조작, 양식 채우기 — kordoc과 겹치는 영역이 있으나 별도 구현체
- **위치**: `~/.claude/bin/rhwp/rhwp.exe` — npm 패키지가 아니라 GitHub 릴리스 바이너리라 `mcp-servers.json`의 `install` 필드로 관리한다. 바이너리 자체는 git에 올리지 않는다(용량·플랫폼별 바이너리라 부적절).
- **MCP 서버 실행**: `rhwp.exe mcp-serve` (stdio JSON-RPC) — `--help`로 서브커맨드 나열해서 확인함(2026-09-10). `capabilities --mcp`로 도구 정의(JSON)만 뽑아볼 수도 있음.
- **설치 자동화 (2026-09-10)**: `setup.ps1`이 바이너리가 없으면 다운로드 여부를 먼저 물어보고, 승인 시 `gh release download`로 받은 뒤 `SHA256SUMS.txt`와 대조해 체크섬이 맞을 때만 설치한다. 동아리 배포 등 제3자 환경에서 조용히 실행 파일을 받아 신뢰시키지 않기 위한 설계 — 자동 다운로드는 하되 사용자 동의 없이는 안 함.
- **버전 추적 안 함**: 이미 설치돼 있으면 그냥 통과하고 최신 버전인지 비교하지 않는다(npm 전역 패키지 체크와 동일한 정책). 로컬에 v0.8.4가 있는데 최신 릴리스는 v0.8.6인 상태를 실제로 확인함(2026-09-10) — 업데이트하려면 `~/.claude/bin/rhwp/` 폴더를 지우고 setup.ps1을 다시 돌려야 한다.

### hwpx-skill (jkf87/hwpx-skill)
- **위치**: `~/.claude/skills/hwpx/` (2026-08-16 이 세션에서 직접 git clone 설치, dotfiles 레포엔 안 올라감 — `.claude/skills`가 gitignore 대상)
- **용도**: HWPX 원본 서식을 보존하며 세부 편집(여백/페이지나누기/문단삽입/쪽번호 등) — kordoc이 못 하는 부분을 보완
- **의존성**: `python-hwpx`, `lxml` (pip install — 파이썬을 재설치하면 같이 날아가니 재설치 필요)
- **필수**: 파이썬 실행 시 항상 `PYTHONUTF8=1` 환경변수를 붙일 것. 안 붙이면 이 환경(콘솔 기본 cp949)에서 유니코드 문자(em dash 등) 포함된 출력(`--help` 등) 시 `UnicodeEncodeError`로 크래시난다(실측 재현됨).
- **주요 명령**:
  - `set-page --margin-mm N`: 여백 설정(제본/거터는 안 건드림)
  - `page-break --para N` / `--after "텍스트"`: 특정 문단에 쪽나누기. `--after`는 문서에 그 텍스트가 유일하게 매치돼야 안전 — 중복되면 엉뚱한 곳에 걸릴 수 있으니 먼저 문단을 전부 나열해 인덱스로 확인하는 게 안전.
  - `add-para --after "텍스트" --text "..."`: 문단 삽입. **앵커 문단의 서식(charPr/run 구조)을 그대로 물려받는다** — 앵커가 굵게·인라인코드 등 섞인 문단이면 삽입된 문단에도 빈 run들이 딸려 나올 수 있어, 순수 본문 스타일 문단을 앵커로 쓰는 게 안전.
  - `set-text-style`: 굵게/기울임/밑줄/색/크기만 지원, **폰트명(font-family)은 못 바꾼다.**
- **폰트**: 새 폰트를 문서에 등록하는 기능은 지원 명령이 마땅찮다 — 이미 문서 폰트 테이블(`header.xml`의 `hh:fontface`)에 있는 폰트를 재사용하는 게 안전. charPr id별 폰트/크기 매핑을 `header.xml`에서 먼저 확인하고 편집할 것.
- **XML 직접 편집 시**: 정규식/문자열 치환보다 **lxml로 DOM 파싱해서 편집하는 게 안전하다.** 문자열 slice로 태그를 직접 자르다가 zip이 통째로 깨진 사고가 실제로 있었다(2026-08-17). 매 단계마다 `zipfile.testzip()`으로 무결성을 즉시 확인할 것.
- **알려진(무관한) 이슈**: 이 hwpx-skill이 만든 원본 zip의 `mimetype` 엔트리가 OCF 규약(STORED)과 달리 DEFLATE로 압축돼 있다고 자체 `validate.py`가 지적함 — kordoc이 최초 생성할 때부터 있던 것으로 추정, 실사용(렌더/파싱/한글에서 열기)엔 지장 없었음. 굳이 안 고쳐도 됨.

### HWPX 학교 과제/보고서 기본 서식 체크리스트

kordoc + hwpx-skill 조합으로 학교 과제용 보고서를 만들 때 확인된 개인 선호 서식. 새 보고서 작업 시 기본값으로 삼고, 과제 공지에 다른 요구사항이 있으면 그것을 우선한다.

- **용지 여백**: 전체 10mm, 제본(거터) 0mm, 세로 방향 — `set-page --margin-mm 10`
- **본문 기본 폰트**: 함초롬돋움 11pt(문서에 이미 등록된 폰트 재사용, charPr height=1100/fontRef.hangul을 해당 id로)
- **문서 구조**: 표지(제목+학과/학번/성명/제출일) → 페이지 나누기 → 목차 → 페이지 나누기 → 본문. kordoc의 `cover`/`toc`는 범용 모드에서 작동 안 하므로, 목차를 마크다운에 직접 써넣고 `page-break`로 수동 분리한다.
- **제목 크기**: 장 제목(H2, "N. 제목") 15pt 굵게, 절 제목(H3, "N.N 제목") 13pt 굵게. 제목은 서술형/의문형 섞지 말고 전부 명사구로 통일.
- **줄간격**: 문서 전체(본문·표지·제목 포함) `lineSpacing` 160%로 통일 — kordoc 기본 생성값은 요소별로 130~180%까지 제각각이라 반드시 확인·수정할 것.
- **장/절 항목 사이 간격**: 문단 속성(`hc:prev`)이 아니라 실제 빈 문단을 삽입한다(`add-para`). 단, 페이지 시작 직후이거나 상위 제목 바로 다음인 경우는 생략.
- **인라인 코드 표기**: 본문과 같은 11pt로 맞춘다(기본 9pt로 생성됨).
- **표는 신중히**: 좌우 열 데이터 길이가 비대칭이면(예: 짧은 라벨 vs 긴 설명) 표 대신 굵은 라벨 + 설명 문단 방식이 더 자연스럽다.
- **나열형 문구**: 가운뎃점(·)으로 여러 항목을 나열할 때 공백 없이 붙이면 한 단어처럼 인식돼 줄바꿈이 부자연스럽다 — 항목 사이 공백을 넣는다(`리서치 · 크리에이티브 · ...`).
- **검증**: 매 편집 후 XML에서 백틱/`**` 리터럴 잔재 전수 스캔 + `render_document`로 시각 확인. 단, `pageBreak`는 렌더러가 반영 안 하므로 별도로 XML 속성 직접 확인.
- **자연 페이지 넘김(콘텐츠가 다 차서 자동으로 넘어가는 지점)은 우리 도구로 예측 불가능하다.** `render_document`는 근사 렌더러라 실제 한글의 정확한 폰트 메트릭·줄바꿈 계산과 다를 수 있다. 정확한 위치가 필요하면 사용자에게 실제 한글/한컴독스에서 확인해달라고 요청하는 수밖에 없다(문단 텍스트 앞뒤로 어디서 넘어가는지 알려달라고 하면 충분).
- **장/절 제목이 페이지 끝에 혼자 남고 내용은 다음 페이지로 넘어가는 "고아 제목" 문제**: 자연 페이지 넘김으로 인해 실제로 발생한다(2026-08-17 실측 확인). 해당 제목 문단에 수동으로 `page-break`를 걸어 제목과 내용이 같은 페이지에서 시작하도록 고치면 된다 — **실제 앱(HOP)에서 정상 작동함을 확인함(2026-08-18)**. `--after` 텍스트가 목차 항목과 겹칠 수 있으니, 문단을 전부 나열해 정확한 인덱스로 `--para`를 쓰는 게 안전(위 "page-break" 항목 참고).
- **HOP(한글 뷰어/편집기)는 HWPX로 저장할 수 없다** — 저장하면 HWP 형식으로 바뀐다(HOP에서 HWPX 저장 미지원, 2026-08-17 확인). "한글에서 한 번 열었다 저장해서 조판 캐시를 얻는" 방법은 HOP로는 불가능하고, 실제 한글(한컴오피스) 정품이나 한컴독스처럼 네이티브 HWPX 저장을 지원하는 도구가 있어야 시도할 수 있다(미검증).

---

## Claude Code 헤드리스(`claude -p`) 실행 시 permission mode 주의사항

**`--model haiku`는 auto mode(classifier 기반 무프롬프트 실행)를 지원하지 않는다.** 공식 문서(2026-08-21, `https://code.claude.com/docs/en/permission-modes`) 확인: "Older models, including Sonnet 4.5, Opus 4.5, Haiku, and claude-3 models, are not supported [for auto mode] on any provider." `~/.claude/settings.json`에 `permissions.defaultMode: "auto"`가 설정돼 있어도, `--model haiku`로 세션을 시작하면 auto mode를 쓸 수 없어 **자동으로 Manual(`default`) 모드로 강등**된다. Manual 모드는 Bash 등 대부분의 도구 호출에 승인이 필요한데, `-p`(비대화형) 헤드리스 실행은 `--permission-prompt-tool` 없이는 승인해줄 방법이 없어서 — 그 도구 호출은 그냥 실행되지 않고 Claude가 "권한 설정이 필요합니다" 같은 설명만 하고 끝난다(에러도 아니고 exit code는 0으로 끝남 — 실패가 조용히 성공처럼 로그에 남을 수 있음, 실측 확인: 개인 자동화 프로젝트의 2026-08-21 뉴스브리핑 job).

- **실측 확인**: 개인 자동화 프로젝트의 dispatcher 스크립트에서 `claude -p prompt --model haiku`로 헤드리스 실행 시, Bash로 python 스크립트를 호출하는 지점에서 위 현상이 재현됨. 같은 조건에서 `--permission-mode bypassPermissions`를 명시하면 정상 실행됨(단, bypassPermissions는 prompt injection에 대한 보호가 전혀 없다고 문서에 명시돼 있어 — 외부 콘텐츠(웹검색 결과 등)를 다루는 무인 파이프라인에 쓰기엔 위험).
- **결론**: Bash/파일쓰기가 필요한 무인(헤드리스) 자동화에서는 `--model haiku`를 쓰지 말 것. `~/.claude/settings.json`의 `defaultMode: "auto"`를 그대로 활용하려면 auto mode가 지원되는 모델(Sonnet 5 이상, Opus 4.6 이상, Fable 5)을 쓴다.
- **대안(미검증)**: 그래도 Haiku로 비용을 아끼고 싶다면 `--permission-mode dontAsk` + 정확한(와일드카드 없는) `permissions.allow` 규칙 조합을 쓰는 방법이 있다(공식 문서가 CI 예시로 권장: `claude -p "..." --permission-mode dontAsk --allowedTools "Bash(npm test)" "Read"`). 단, auto mode의 classifier는 "`Bash(python*)`처럼 와일드카드 인터프리터 패턴"을 진입 시 자동으로 무시하지만 dontAsk 모드는 그 드롭 로직이 없어 와일드카드 allow 규칙이 그대로 적용된다 — 다만 Write 등 파일쓰기 도구도 dontAsk에서는 별도로 allow해야 해서 설정이 늘어난다. 실제로 시도해보지 않았음.
- **관찰됐지만 원인 미확정인 별개 현상**: 같은 날 같은 모델로 실행된 다른 슬래시 커맨드 job들은 작업 디렉터리 밖 레포 경로 접근이 job마다 다르게(어떤 날은 되고 어떤 날은 "권한 없음"으로 실패) 나타남 — Manual/auto 모드에서 작업 디렉터리 밖 경로는 별도 승인·classifier 판단이 필요하다는 문서 내용과 관련 있어 보이지만 확정 짓지 못함. 재현 조건을 더 좁혀봐야 함.

### `allowed-tools`는 제한이 아니라 부여다 — 무인 에이전트 도구 차단엔 `disallowed-tools`/`--disallowedTools`를 써야 한다

**슬래시 커맨드 frontmatter의 `allowed-tools`는 나열한 도구를 "허용"할 뿐, 나열 안 된 다른 도구를 "제거"하지 않는다.** 공식 문서(`code.claude.com/docs/en/skills`, v2.1.238 기준, 2026-08-22 확인) 원문: *"The `allowed-tools` field grants permission for the listed tools during the turn... It does not restrict which tools are available: every tool remains callable, and your permission settings still govern tools that are not listed."*

이 착각으로 실수한 사례: 어느 개인 자동화 프로젝트의 슬래시 커맨드에 `allowed-tools: mcp__tavily__tavily_search`만 적어두고 "Bash가 없으니 안전하다"고 판단했는데, 실제로는 Bash가 전혀 제거되지 않은 상태였다(permission mode에 따라 여전히 호출·승인 가능). `allowed-tools`만으로는 **무인(헤드리스) 에이전트의 도구를 실제로 박탈할 수 없다.**

**실제로 도구를 제거하는 수단은 둘, 강도가 다르다(실측 A/B 비교, 2026-08-22):**
- **`--disallowedTools "<도구명>..." `(CLI 플래그, 가장 강함)**: 세션의 도구 풀 자체에서 삭제한다 — `--output-format json`의 init 이벤트에서 `tools: []`로 확인됨. 모델이 도구를 쓰려고 시도해도 애초에 노출된 도구가 없어 `tool_use` 블록 자체가 0개 생성됨. MCP 서버까지 전부 빼려면 `--strict-mcp-config`(즉 `--mcp-config` 없이 이 플래그만 켜면 MCP 서버가 하나도 안 실림)를 같이 쓴다. **단, `--strict-mcp-config`를 쓰면 필요한 MCP 도구(예: tavily 검색)까지 같이 죽는다** — 특정 MCP 도구는 살리고 Bash/PowerShell 같은 실행 도구만 죽이려면 `--disallowedTools "Bash" "PowerShell"`처럼 이름을 콕 집어서 deny하고 `--strict-mcp-config`는 빼야 한다.
- **frontmatter `disallowed-tools: "*"` (또는 특정 도구명)**: 도구가 스키마상으론 남아있지만 호출을 시도하면 `"Permission to use Bash has been denied."`로 거부된다(프롬프트 순종이 아니라 실제 강제됨, A/B 프로브로 확인). CLI 플래그보다는 약하지만(도구 존재 자체는 남음) 그래도 실제로 막는다.
- **결론**: 무인 에이전트는 **CLI `--disallowedTools`(+ 필요시 `--strict-mcp-config`)를 반드시 걸고**, frontmatter `disallowed-tools`도 defense-in-depth로 같이 건다(개인 자동화 프로젝트의 슬래시 커맨드 두 건에서 둘 다 확인). `allowed-tools`만 좁혀놓고 안전하다고 판단하지 말 것 — [[feedback_no_exec_perms_unsupervised_agents]] 참고.

---

## 스킬 (개인, `~/.claude/skills/`)

- **cluedoc**, **dev-server**: 각자 폴더의 `SKILL.md` 참조. 여기 별도 요약은 아직 없음 — 필요할 때 직접 열어볼 것.
- **hwpx**: 위 "hwpx-skill" 참조.

## 플러그인

### superpowers
- **자동 업데이트됨**: 설치 후에도 `lastUpdated`가 계속 갱신되는 것 확인됨.
- **호출 원칙**: 표에 없는 상황이라도 1%라도 맞으면 반드시 먼저 호출한다(`CLAUDE.md` B6). 아래 표는 대표 예시일 뿐이다 — 갱신되면 같이 최신화한다.

| 상황 | 호출 스킬 |
|------|-----------|
| 새 기능 구현, 컴포넌트 추가, 동작 변경 전 | `superpowers:brainstorming` |
| 버그, 테스트 실패, 예상치 못한 동작 발생 시 | `superpowers:systematic-debugging` |
| 코드 리뷰 피드백 수신 시 | `superpowers:receiving-code-review` |
| 구현 완료 또는 수정 완료를 주장하기 전 | `superpowers:verification-before-completion` |
| 다단계 구현 계획 실행 시 | `superpowers:executing-plans` |
| 독립적인 작업 2개 이상 병렬 처리 시 | `superpowers:dispatching-parallel-agents` |
| 스펙/요구사항을 받아 구현 시작 전 | `superpowers:writing-plans` |
| 기능 구현에 TDD 적용 시 | `superpowers:test-driven-development` |
| 작업 완료 후 머지/PR 결정 시 | `superpowers:finishing-a-development-branch` |
| 작업/주요 기능 완료 후 리뷰 요청 시 | `superpowers:requesting-code-review` |
| 독립적 작업들을 현재 세션에서 서브에이전트로 실행 시 | `superpowers:subagent-driven-development` |
| 현재 작업공간과 격리가 필요한 기능 작업 시작 시 | `superpowers:using-git-worktrees` |
| 새 스킬 작성 또는 기존 스킬 수정 시 | `superpowers:writing-skills` |

- **스킬 자체의 세부 동작**(예: `subagent-driven-development`의 정확한 단계)은 그때그때 스킬 파일을 직접 읽는 게 최신 내용을 보장한다(업데이트되므로).
