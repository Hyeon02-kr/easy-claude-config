# easy-claude-config

Claude Code 전역 설정(지침 문서, MCP 서버 구성, 슬래시 명령)을 한 번에 세팅하기 위한 레포입니다. `setup.ps1` 하나로 MCP 서버 등록과 전역 패키지 설치까지 처리하고, 원하지 않는 항목은 체크 해제할 수 있습니다.

> **Windows 전용입니다.** `setup.ps1`은 PowerShell 스크립트이고, MCP 실행 명령도 `cmd /c` 기준입니다. Windows PowerShell 5.1에서 동작을 확인했습니다(PowerShell 7은 미검증).
>
> **기본값은 작성자 개인 설정입니다.** 특히 `CLAUDE.md`(Part B·C)와 `settings.example.json`은 작성자의 취향과 실패 경험이 그대로 들어 있으니, [쓰기 전에 확인하세요](#쓰기-전에-확인하세요)를 먼저 읽어 주세요.

## 무엇이 들어 있나요

| 파일 | 설명 |
|------|------|
| `.claude/CLAUDE.md` | 전역 지침. Part A는 범용 코딩 원칙, Part B는 개인 설정, Part C는 실제로 반복 지적받아 만들어진 규칙 |
| `.claude/TOOLS.md` | MCP·스킬·플러그인별 사용 트리거와 실측으로 확인한 제약. `CLAUDE.md`가 이 문서를 참조합니다 |
| `.claude/mcp-servers.json` | MCP 서버 선언(단일 진실 원천). `setup.ps1`이 이 파일을 읽습니다 |
| `.claude/mcp-secrets.example.json` | API 키가 필요한 서버를 위한 비밀값 양식 |
| `.claude/settings.example.json` | `settings.json` 초기 템플릿 |
| `.claude/scripts/discord-notify.py` | 작업 완료·권한 요청 등을 Discord Webhook으로 알리는 훅(선택) |
| `.claude/commands/` | 커스텀 슬래시 명령 `init`, `codereview`, `codefix` |
| `setup.ps1` | 위 구성을 실제 환경에 반영하는 동기화 스크립트 |

git이 **추적하지 않는** 로컬 전용 파일입니다.

| 파일 | 이유 |
|------|------|
| `.claude/settings.json` | 개인별 라이브 설정입니다. 없으면 `setup.ps1`이 `settings.example.json`을 복사해 만들고, 이미 있으면 절대 건드리지 않습니다 |
| `.claude/mcp-secrets.json` | API 키 등 비밀값입니다. 직접 만듭니다 |
| `.claude/scripts/discord-config.json` | Webhook URL입니다. 선택하면 `setup.ps1`이 생성합니다 |
| `.claude/bin/` | 내려받은 실행 파일(rhwp)입니다 |

`TOOLS.md`를 세션 시작·compact 후에 자동으로 읽게 하는 훅은 작성자의 로컬 설정이며 이 레포에는 포함돼 있지 않습니다. 필요하면 직접 훅을 만들거나, 그냥 참고 문서로 쓰시면 됩니다.

## 빠른 시작

### 0. 사전 프로그램

| 프로그램 | 용도 | 설치 |
|----------|------|------|
| [Node.js](https://nodejs.org/) (LTS, npm 포함) | npm 기반 MCP 서버 실행·설치 | `winget install OpenJS.NodeJS.LTS` |
| [Git](https://git-scm.com/) | 이 레포 받기, 훅 실행 셸(Git Bash) | `winget install Git.Git` |
| [GitHub CLI](https://cli.github.com/) | rhwp 바이너리 다운로드 | `winget install GitHub.cli` |
| [Python](https://www.python.org/downloads/) | Discord 알림 훅. 안 쓰면 없어도 되지만 `setup.ps1`이 없다고 경고는 합니다 | `winget install Python.Python.3` |
| [Claude Code](https://claude.ai/code) | 본체 | 공식 사이트 참조 |

Claude Code 설치 스크립트는 Node.js를 함께 설치하지 않습니다(설치 스크립트에 Node.js 설치·검사 단계가 없음을 확인했습니다). Node.js는 따로 설치해야 합니다. `setup.ps1`은 이 프로그램들이 있는지 점검만 하고 설치하지는 않습니다.

### 1. 홈 디렉터리에 받기

**반드시 홈 디렉터리(`C:\Users\<사용자명>`)가 레포 루트여야 합니다.** Claude Code가 `~/.claude`를 읽기 때문입니다. 홈에는 이미 파일이 있으므로 `git clone <URL> .`은 "이미 존재하는 비어있지 않은 디렉터리"라며 실패합니다. 대신 이렇게 받습니다.

```powershell
cd $env:USERPROFILE
git init -b main
git remote add origin https://github.com/Hyeon02-kr/easy-claude-config.git
git fetch origin main
git checkout -b main origin/main
```

이미 `~/.claude/CLAUDE.md` 같은 파일이 있으면 `checkout`이 "덮어써질 파일" 목록을 보여주며 **중단**합니다(기존 파일은 그대로 보존됩니다). 목록의 파일을 다른 곳으로 옮겨 백업한 뒤 `git checkout -b main origin/main`을 다시 실행하세요.

### 2. (필요한 경우) 비밀값 파일 만들기

Context7은 API 키가 필요합니다. 키가 필요한 서버를 쓸 때만 하면 됩니다.

```powershell
Copy-Item .claude\mcp-secrets.example.json .claude\mcp-secrets.json
notepad .claude\mcp-secrets.json
```

`PLACEHOLDER_...` 자리에 실제 키를 넣고, 쓰지 않는 예시 항목은 지우세요. **이 파일은 직접 편집기로 여세요.** Claude 세션 안에서 열거나 내용을 붙여넣으면 키가 대화 로그에 남습니다. 키가 없으면 `setup.ps1`이 해당 서버만 건너뛰고 경고합니다.

### 3. 동기화 스크립트 실행

```powershell
.\setup.ps1
```

순서는 다음과 같습니다.

1. **설정 파일** — `settings.json`이 없으면 `settings.example.json`에서 만듭니다
2. **설치 옵션 선택** — 설치할 MCP 서버와 Discord 알림을 체크박스로 고릅니다. 스페이스로 선택/해제, 위·아래 화살표로 이동, 엔터로 확정합니다(기본값은 전체 선택). 리다이렉션 등으로 체크박스를 그릴 수 없는 환경이면 번호를 입력하는 방식으로 자동 전환됩니다
3. **사전 프로그램 점검**
4. **전역 npm 패키지** 설치
5. **MCP 서버 등록** — 선택한 것만 처리합니다. 선택하지 않은 항목은 건너뛸 뿐, 이미 등록된 서버를 지우지는 않습니다
6. **비밀 파일 점검** — Discord를 선택했고 설정이 없으면 Webhook URL을 물어봅니다(비우면 건너뜀)

마지막에 결과 요약과 함께 **직접 해야 할 일 목록**이 맨 아래에 출력됩니다.

### 4. 직접 해야 하는 일

스크립트가 자동화할 수 없는 부분입니다. 실행 마지막의 "다음 할 일"에도 똑같이 나옵니다.

- Claude Code에서 `/mcp` → `tavily`, `notion` 선택 → 브라우저 인증(OAuth)
- Claude Code에서 `/plugin install superpowers@claude-plugins-official`
- 터미널에서 `gh auth login`

## setup.ps1 옵션

| 옵션 | 동작 |
|------|------|
| (없음) | 변경을 적용합니다 |
| `-Check` / `-c` / `--check` | 아무것도 바꾸지 않고 선언과 실제의 차이만 보고합니다. 프롬프트 없이 전체 선택으로 점검하며, 경고가 있으면 종료 코드 1을 반환합니다 |
| `-Force` / `-f` / `--force` | 선언과 어긋난 MCP 서버를 지우고 매니페스트대로 다시 등록합니다. 무엇이 지워지는지 먼저 보여주고 확인을 받습니다 |

확인 프롬프트는 `y`/`n`만 입력하면 되고, 그냥 엔터를 치면 기본값인 **아니오**입니다. 몇 번을 실행해도 결과가 같습니다(멱등).

`-Check`가 "MCP 명령 불일치"를 보고하면 선언과 실제 중 어느 쪽이 최신인지는 사람이 판단합니다. 스크립트가 알아서 덮어쓰지 않습니다.

## MCP 서버

| MCP | 용도 | 설치 방식 | 인증 |
|-----|------|-----------|------|
| context7 | 라이브러리·프레임워크 최신 문서 | 전역 npm 패키지(자동 설치) | **API 키** (`mcp-secrets.json`) |
| playwright | 브라우저 자동화·UI 테스트 | `npx` | 불필요 |
| kordoc | 한국어 문서(HWP/HWPX/PDF 등) 파싱·생성 | 전역 npm 패키지(자동 설치) | 불필요 |
| tavily | 웹 검색 | 원격 HTTP | **브라우저 OAuth** (`/mcp`) |
| notion | Notion 페이지·DB 검색·편집 | 원격 HTTP | **브라우저 OAuth** (`/mcp`) |
| rhwp | HWP/HWPX/HML 렌더링·구조 추출 | **GitHub 릴리스 바이너리** | 불필요 |

- **rhwp**는 npm 패키지가 아니라 실행 파일이라, 없으면 내려받을지 먼저 묻습니다(기본값 아니오). 승인하면 `gh release download`로 받은 뒤 `SHA256SUMS.txt`와 대조해 **체크섬이 맞을 때만** `.claude/bin/rhwp/`에 설치합니다. `gh`가 로그인돼 있지 않으면 실패할 수 있으니 `gh auth login`을 먼저 해 두시길 권합니다.
- 이미 설치된 rhwp는 버전 비교를 하지 않습니다. 업데이트하려면 `.claude/bin/rhwp/`를 지우고 `setup.ps1`을 다시 실행하세요.
- 정확한 정의는 `.claude/mcp-servers.json`에 있습니다. 서버를 추가·변경할 때는 그 파일을 고치고 `setup.ps1`을 다시 돌립니다.
- Google Drive·Gmail·Google Calendar는 claude.ai 계정 커넥터라 계정에 붙어 있고, 기계별 설치가 필요 없습니다.

## 쓰기 전에 확인하세요

`settings.example.json`이 `settings.json`의 초기값이 됩니다(이미 `settings.json`이 있으면 그대로 두므로 자동 병합되지 않습니다). 아래 값들이 본인 취향과 맞는지 확인하세요.

| 설정 | 기본값 | 의미 |
|------|--------|------|
| `permissions.defaultMode` | `auto` | 분류기가 도구 호출을 자동 판단합니다. 매번 확인받고 싶다면 `default`로 바꾸세요 |
| `skipDangerousModePermissionPrompt` | `true` | bypass permissions 모드의 경고 대화상자를 이미 수락한 것으로 취급합니다 |
| `remoteControlAtStartup` | `true` | 시작 시 Remote Control을 켭니다 |
| `language` / `model` | `한국어` / `Sonnet` | 응답 언어와 기본 모델 |
| `hooks` | Discord 알림 4종 | `discord-config.json`이 없으면 훅이 아무 일도 하지 않습니다 |
| `permissions.deny` | 비밀 파일·`claude mcp get/list` | Claude가 비밀 파일을 읽거나 MCP 등록 정보(키가 섞일 수 있음)를 출력하지 못하게 막습니다. 이 규칙은 Claude 세션에만 적용되며, 직접 터미널에서 실행하는 건 막지 않습니다 |

`CLAUDE.md`는 **작성자의 개인 규칙**입니다. 예를 들어 B4는 "커밋·푸시는 매번 승인", B7은 "코딩 기본 모델은 Sonnet, 모델은 항상 최신 버전만", B9는 커밋 메시지 형식(`type: 제목`)을 강제합니다. 그대로 쓰기보다 본인 방식에 맞게 고쳐 쓰는 것을 전제로 만들어졌습니다. 이 규칙을 바꾸고 싶다면 이 레포를 포크해서 쓰시는 편이 `git pull` 충돌을 피하기 좋습니다.

## 업데이트

```powershell
git pull
.\setup.ps1
```

`CLAUDE.md` 등을 직접 수정했다면 pull 시 충돌할 수 있습니다. 위에서 말씀드린 대로 포크해서 본인 레포를 `origin`으로 쓰는 방식이 편합니다.

## 트러블슈팅

**Discord 알림이 안 옵니다**
- `.claude/scripts/discord-config.json`이 있는지 확인하세요. 없으면 `setup.ps1`을 다시 실행해 Discord를 선택합니다.
- 훅은 설정이 없거나 전송에 실패하면 조용히 종료하고 `.claude/scripts/hook-debug.log`에 예외를 남깁니다. 원인은 그 파일에서 확인할 수 있습니다.

**kordoc이 연결되지 않습니다**
- `npx`로 띄우면 콜드스타트가 약 38초라 Claude Code의 30초 연결 타임아웃을 넘깁니다. 그래서 전역 설치 후 `kordoc-mcp`를 직접 실행하도록 등록합니다(`mcp-servers.json`의 note 참조).
- 전역 설치 시 일부 패키지의 postinstall이 npm 11의 allow-scripts 정책으로 차단되지만 기본 연결에는 영향이 없습니다. 이미지·OCR 기능이 실패하면 `npm approve-scripts`로 허용하세요.

**tavily / notion이 "Needs authentication"으로 나옵니다**
- 원격 서버라 브라우저 OAuth가 필요합니다. Claude Code에서 `/mcp` → 해당 서버 → 인증하세요. 새 기계마다 한 번씩 해야 하며 스크립트로 자동화할 수 없습니다.

**MCP 서버 상태를 보고 싶습니다**
- Claude Code 세션에서 `/mcp`, 또는 본인 터미널에서 `claude mcp list`(Claude 세션 안에서는 위 deny 규칙으로 막혀 있습니다)
- 선언과의 차이는 `.\setup.ps1 -Check`

**`setup.ps1`의 한국어가 깨져 보입니다**
- Windows PowerShell 5.1은 BOM 없는 UTF-8 스크립트를 ANSI 코드페이지로 읽습니다. `setup.ps1`은 UTF-8 BOM을 포함해야 하며, 편집기에서 BOM을 떼고 저장하면 출력이 깨지고 파싱까지 실패할 수 있습니다.

## 라이선스

이 저장소는 **참고용으로 공개**되어 있으며, 재사용·재배포·수정본 배포는 허용하지 않습니다. 별도의 LICENSE 파일이 없으므로 저작권법의 기본값(모든 권리 보유)이 적용됩니다. 저장소를 보는 것과 GitHub 기능을 통한 포크는 [GitHub 이용 약관](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service)에 따라 가능합니다. 사용 허락이 필요하면 저장소 소유자에게 문의해 주세요.
