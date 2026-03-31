# Architecture Overview

## 목표
이 프로젝트는 패러글라이딩 클럽 구성원과 초급 조종사를 위한 의사결정 지원 MVP입니다.  
핵심은 "오늘 어느 사이트가 상대적으로 안전한가"를 룰베이스로 빠르게 보여주는 것입니다.

## 구성
- `backend/`
  - FastAPI REST API
  - SQLAlchemy ORM
  - Alembic 마이그레이션
  - seed 스크립트
  - 룰베이스 비행 판단 로직
- `frontend/`
  - Flutter 앱
  - 로그인, 홈, 사이트 목록/상세, 비행 기록, 훈련 기록, 공지 화면
  - `MockAppRepository` 와 `ApiAppRepository` 분리
- `frontend/lib/core/flight_record_manager.dart`
  - 비행 기록 제어
  - 위치 추적
  - 로컬 저장
  - 공유용 JSON 생성
- `docker-compose.yml`
  - PostgreSQL 로컬 실행용

## 비행 판단 로직
입력:
- 사이트별 허용 풍향 범위
- 조종 레벨별 최대 평균 풍속
- 최대 돌풍
- 최대 돌풍 편차
- 강수 허용 여부
- 초급 허용 여부

출력:
- `score`
- `status`
- `reasons`
- `summary_text`

기본 계산:
1. 100점에서 시작
2. 풍향 이탈, 풍속 초과, 돌풍 초과, 돌풍 편차 초과, 강수, 초급 제한 항목별 감점
3. 최종 점수 기준으로 `good`, `caution`, `bad` 산정

## 실행 전략
- 백엔드는 PostgreSQL 기준으로 실행하되, `.env`가 없을 때는 SQLite fallback으로도 동작합니다.
- 프론트는 기본적으로 mock API로 즉시 실행됩니다.
- 실제 백엔드 연결은 `--dart-define=USE_MOCK_API=false` 와 `--dart-define=API_BASE_URL=...` 로 전환합니다.
- 비행 기록은 네트워크와 무관하게 기기에 먼저 저장한 뒤, 저장 완료 후 JSON 파일로 공유합니다.
- 현재 비행 기록은 전경 추적 MVP이며, 백그라운드 연속 추적은 포함하지 않습니다.
