# Claude Code 전역 환경 설정

Claude Code 전역 설정 파일 모음. 노트북과 데스크탑에서 거의 동일한 환경을 유지하기 위한 레포다.

**반드시 홈 디렉터리(`C:\Users\<사용자명>`)에 클론해야 한다.** 레포 루트가 곧 `~`이다.

## 동기화 구조

| 담당 | 대상 |
|------|------|
| **git** | `settings.json`, `CLAUDE.md`, `commands/`, `scripts/`, `statusline.py`, `mcp-servers.json`, `GEMINI.md` |
| **`setup.ps1`** | git이 옮길 수 없는 것: MCP 서버 등록, 전역 npm 패키지, 비밀 파일 생성 |
| **수동** | tavily OAuth 인증, `gh auth login`, superpowers 플러그인 설치 |

추적되는 파일에는 절대경로·사용자명·API 키를 넣지 않는다. 훅 경로는 `$HOME` 기준으로 적혀 있어 사용자명이 달라도 그대로 동작한다.

## 포함된 파일

| 파일 | 설명 |
|------|------|
| `.claude/CLAUDE.md` | 전역 코딩 철학 및 MCP/Superpowers 사용 지침 |
| `.claude/settings.json` | 권한·훅·모델·statusLine 등 전역 설정 |
| `.claude/mcp-servers.json` | MCP 서버 선언 (단일 진실 원천) |
| `.claude/statusline.py` | 하단 상태 표시줄 |
| `.claude/scripts/discord-notify.py` | 알림 → Discord 전송 훅 |
| `.claude/scripts/devserver.py` | 개발 서버 관리 훅 |
| `.claude/scripts/epoche.py` | 판단 중지(epoché) 훅 |
| `.claude/commands/` | 커스텀 슬래시 명령 (`init`, `codereview`, `codefix`, `epoche`) |
| `.gemini/GEMINI.md` | Antigravity(Google) 전역 코딩 지침 |

git에 **포함되지 않는** 것:

| 파일 | 이유 |
|------|------|
| `~/.claude/scripts/discord-config.json` | Webhook URL. `setup.ps1`이 생성 |
| `~/.claude.json` | `machineID`·`userID`·OAuth 계정·프로젝트 절대경로가 섞여 있다. MCP 설정은 `setup.ps1`이 `mcp-servers.json`을 보고 재구성한다 |

---

## 사전 설치 프로그램

| 프로그램 | 용도 | 설치 |
|----------|------|------|
| [Python](https://www.python.org/downloads/) | 상태 표시줄, 훅 스크립트 | `winget install Python.Python.3` |
| [Node.js](https://nodejs.org/) (LTS) | MCP 서버 실행 | `winget install OpenJS.NodeJS.LTS` |
| [Git](https://git-scm.com/) | 버전 관리, 훅 실행 셸(Git Bash) | `winget install Git.Git` |
| [GitHub CLI](https://cli.github.com/) | PR·이슈 작업 | `winget install GitHub.cli` |
| [Claude Code](https://claude.ai/code) | 메인 도구 | 공식 사이트 참조 |

`setup.ps1`이 존재 여부를 점검해주지만 설치는 하지 않는다.

---

## 설치 방법

### 1. 홈 디렉터리에 클론

```powershell
cd $env:USERPROFILE
git clone <레포 URL> .
```

### 2. 동기화 스크립트 실행

```powershell
.\setup.ps1
```

Discord Webhook URL만 물어본다. 비우면 건너뛴다.

**이 스크립트는 멱등하다.** 몇 번 돌려도 결과가 같고, 이미 맞는 항목은 건너뛴다. `settings.json`은 건드리지 않는다 — 그 파일은 git이 관리하므로 pull만 받으면 된다.

### 3. 수동 작업

Claude Code를 열고:

```
/plugin install superpowers@claude-plugins-official
/mcp                                    → tavily 선택 → 브라우저 인증
```

터미널에서:

```powershell
gh auth login
```

---

## 평소 사용법

**노트북에서 바꾼 것을 데스크탑에 반영:**

```powershell
# 노트북
git add -A; git commit -m "설정 변경"; git push

# 데스크탑
git pull
.\setup.ps1        # MCP·패키지 차이만 반영. settings.json은 pull로 이미 반영됨
```

**선언과 실제가 어긋났는지 점검:**

```powershell
.\setup.ps1 -Check
```

아무것도 변경하지 않고 차이만 보고한다. 경고가 있으면 종료 코드 1을 반환한다. MCP 서버를 수동으로 추가하거나 명령을 바꿨을 때 `mcp-servers.json`과 벌어진 차이를 잡아낸다.

`-Check`가 "MCP 명령 불일치"를 보고하면 어느 쪽이 최신인지는 사람이 판단한다. 스크립트는 자동으로 덮어쓰거나 삭제하지 않는다.

---

## 등록되는 MCP 서버

| MCP | 용도 | 설치 방식 | 인증 |
|-----|------|-----------|------|
| Context7 | 라이브러리·프레임워크 최신 문서 | `npx` (설치 불필요) | 불필요 |
| Sequential Thinking | 다단계 문제 추론 | `npx` (설치 불필요) | 불필요 |
| Playwright | 브라우저 자동화·UI 테스트 | `npx` (설치 불필요) | 불필요 |
| kordoc | 한국어 문서 파싱·생성·양식 처리 | **전역 설치 필요** (`npm i -g kordoc`) | 불필요 |
| Tavily | 웹 검색 | 원격 HTTP | **브라우저 OAuth** (`/mcp`) |

정확한 정의는 `.claude/mcp-servers.json`에 있다. 서버를 추가·변경할 때는 그 파일을 고치고 `setup.ps1`을 다시 돌린다.

Google Drive·Gmail·Google Calendar는 claude.ai 계정 커넥터라 계정에 붙어 있고 기계별 설치가 필요 없다.

---

## 트러블슈팅

**상태 표시줄이 안 보인다**
- Python이 PATH에 있는지 확인
- Git Bash가 설치되어 있는지 확인 (훅과 statusLine이 Git Bash를 경유한다)

**Discord 알림이 안 온다**
- `~/.claude/scripts/discord-config.json`이 있는지 확인. 없으면 `setup.ps1` 재실행
- 이 파일이 없으면 훅이 발화할 때마다 `discord-notify.py`가 `FileNotFoundError`로 죽는다. `~/.claude/scripts/hook-debug.log`에서 확인할 수 있다

**kordoc이 연결되지 않는다**
- `npx`로 띄우면 콜드스타트가 약 38초라 30초 연결 타임아웃을 넘긴다. 전역 설치가 필수다: `npm i -g kordoc`
- 패키지가 bin을 둘로 제공한다. `kordoc`은 CLI, `kordoc-mcp`가 MCP 서버다
- 전역 설치 시 sharp / onnxruntime-node / protobufjs의 postinstall이 npm 11의 allow-scripts 정책으로 차단되는데 기본 연결에는 영향이 없다. 이미지·OCR 기능이 실패하면 `npm approve-scripts`로 허용한다

**Tavily가 연결되지 않는다**
- 원격 서버라 브라우저 OAuth가 필요하다. `/mcp` → tavily → 인증
- 새 기계마다 한 번씩 해야 하고 스크립트로 자동화할 수 없다

**MCP 서버 상태를 보고 싶다**
- Claude Code 세션에서 `/mcp`
- 터미널에서 `claude mcp list`
- 선언과의 차이는 `.\setup.ps1 -Check`

**`setup.ps1`의 한국어가 깨져 보인다**
- Windows PowerShell 5.1은 BOM 없는 UTF-8 스크립트를 ANSI 코드페이지로 읽는다. `setup.ps1`은 UTF-8 BOM을 포함해야 하며, 편집기에서 BOM을 떼고 저장하면 출력이 깨지고 파싱까지 실패할 수 있다

**훅이 다른 기계에서 동작하지 않는다**
- `settings.json`의 훅 명령에 절대경로가 들어갔는지 확인한다. `$HOME` 기준이어야 한다:
  ```powershell
  Select-String -Path .claude\settings.json -Pattern "Users"
  ```
  출력이 있으면 절대경로가 섞인 것이다
