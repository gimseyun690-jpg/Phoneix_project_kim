# Paragliding MVP

패러글라이딩 클럽용 의사결정 지원 MVP입니다.  
Flutter 프론트엔드, FastAPI 백엔드, PostgreSQL, Alembic, seed 데이터를 포함합니다.

## Repository Structure

```text
frontend/
backend/
docs/
README.md
.env.example
docker-compose.yml
AGENTS.md
```

## MVP 포함 기능

- 로그인 스캐폴드
- 홈 화면 추천 사이트 카드
- 사이트 목록 / 사이트 상세
- 비행 기록 시작 / 저장 / 히스토리 / 상세 / 공유
- 훈련 기록 작성 / 조회
- 공지 목록 / 상세
- 관리자용 사이트 기준 / 공지 생성·수정 API
- 룰베이스 비행 판단 결과

## Backend Overview

- 엔트리포인트: `backend/app/main.py`
- FastAPI 경로:
  - `/api/v1/auth/login`
  - `/api/v1/home`
  - `/api/v1/sites`
  - `/api/v1/weather/sites/{site_id}/latest`
  - `/api/v1/assessments/sites/{site_id}`
  - `/api/v1/training-logs`
  - `/api/v1/notices`
  - `/api/v1/admin/site-rules`
  - `/api/v1/admin/notices`
- 시드 데이터:
  - 사용자 2명
  - 사이트 4개
  - 사이트 기준 4개
  - 날씨 스냅샷 4개
  - 훈련 기록 3개
  - 공지 3개

## Frontend Overview

- 엔트리포인트: `frontend/lib/main.dart`
- 기본 모드: mock repository
- 비행 기록:
  - 전경 위치 추적 기반
  - 로컬 우선 저장
  - JSON 파일 공유
- 실 API 연결:
  - `USE_MOCK_API=false`
  - `API_BASE_URL=http://127.0.0.1:8000/api/v1`

## Exact Run Steps

아래 명령은 WSL 기준입니다. 저장소 루트가 `/mnt/c/Users/김세윤1/Desktop/para_project` 라고 가정합니다.

### 1. 저장소 루트로 이동

```bash
cd /mnt/c/Users/김세윤1/Desktop/para_project
```

### 2. 환경 파일 준비

```bash
cp .env.example .env
```

### 3. PostgreSQL 실행

```bash
docker compose up -d postgres
```

### 4. 백엔드 가상환경 및 패키지 설치

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r backend/requirements.txt
```

### 5. Alembic 마이그레이션 적용

```bash
cd backend
alembic upgrade head
cd ..
```

### 6. 시드 데이터 입력

```bash
python backend/scripts/seed.py
```

### 7. 백엔드 실행

```bash
cd backend
uvicorn app.main:app --reload
```

브라우저 확인:

```text
http://127.0.0.1:8000/docs
http://127.0.0.1:8000/health
```

### 8. 프론트엔드 실행 - mock 데이터 모드

새 터미널에서:

```bash
cd /mnt/c/Users/김세윤1/Desktop/para_project/frontend
flutter pub get
flutter run -d chrome
```

### 9. 프론트엔드 실행 - 실제 백엔드 연결 모드

새 터미널에서:

```bash
cd /mnt/c/Users/김세윤1/Desktop/para_project/frontend
flutter pub get
flutter run -d chrome \
  --dart-define=USE_MOCK_API=false \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```

## Sample Credentials

- 일반 사용자: `pilot@parawing.local` / `pilot123`
- 관리자: `admin@parawing.local` / `admin123`

## Seeded Example Sites

- 양평 패러밸리: 초급 친화
- 단양 리지포인트: 중급 훈련용
- 제주 코스탈 클리프: 숙련자 중심
- 문경 활공랜드: 계곡풍 판단 연습용

## Sample Files

- 샘플 API 응답: `backend/sample_responses/`
- 구조 요약: `docs/overview.md`

## Notes

- WSL이 정상 동작하지 않거나 Flutter SDK가 PATH에 없으면 프론트 실행 전 SDK 설정이 필요합니다.
- 백엔드는 `.env`가 없으면 SQLite fallback으로도 동작하도록 만들어 두었습니다.
- 비행 기록 기능은 현재 MVP 기준으로 전경 추적 방식입니다. 앱이 닫히거나 백그라운드에서 강제 종료되면 위치 기록이 중단될 수 있습니다.
- 위치 기록을 사용하려면 브라우저 또는 기기에서 위치 권한을 허용해야 합니다.
