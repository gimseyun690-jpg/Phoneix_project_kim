from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

from sqlalchemy import delete
from sqlalchemy.orm import Session

from app.models.enums import PilotLevel
from app.models.flight_assessment import FlightAssessment
from app.models.flying_site import FlyingSite
from app.models.notice import Notice
from app.models.site_rule import SiteRule
from app.models.training_log import TrainingLog
from app.models.user import User
from app.models.weather_snapshot import WeatherSnapshot
from app.services.assessment import assess_flight


def _hourly_forecast(
    base_speed: float,
    base_direction: int,
    base_gust: float,
    precipitation_mm: float | None = None,
) -> list[dict]:
    return [
        {
            "time_label": label,
            "average_wind_speed": round(base_speed + speed_delta, 1),
            "wind_direction": base_direction + direction_delta,
            "gust_speed": round(base_gust + gust_delta, 1),
            "precipitation_mm": precipitation_mm,
        }
        for label, speed_delta, direction_delta, gust_delta in [
            ("09:00", -0.3, -10, -0.2),
            ("12:00", 0.0, 0, 0.0),
            ("15:00", 0.4, 8, 0.5),
            ("18:00", -0.5, -5, -0.4),
        ]
    ]


def seed_database(db: Session) -> None:
    now = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)

    db.execute(delete(FlightAssessment))
    db.execute(delete(TrainingLog))
    db.execute(delete(WeatherSnapshot))
    db.execute(delete(SiteRule))
    db.execute(delete(Notice))
    db.execute(delete(FlyingSite))
    db.execute(delete(User))
    db.commit()

    users = [
        User(
            id=1,
            email="admin@parawing.local",
            full_name="관리자",
            password="admin123",
            pilot_level="advanced",
            is_admin=True,
        ),
        User(
            id=2,
            email="pilot@parawing.local",
            full_name="김초급",
            password="pilot123",
            pilot_level="beginner",
            is_admin=False,
        ),
    ]

    sites = [
        FlyingSite(
            id=1,
            name="양평 패러밸리",
            region="경기",
            difficulty="beginner",
            short_description="초급자 훈련과 클럽 비행에 자주 쓰이는 완만한 능선 사이트",
            description="남서풍 계열에서 비교적 안정적이며, 교육 비행과 팀 브리핑에 많이 사용됩니다.",
            takeoff_altitude_m=640,
            landing_altitude_m=180,
        ),
        FlyingSite(
            id=2,
            name="단양 리지포인트",
            region="충북",
            difficulty="intermediate",
            short_description="열활공과 크로스컨트리 입문에 적합한 대표 리지 사이트",
            description="풍향이 맞으면 좋은 상승대를 기대할 수 있지만, 오후 돌풍을 확인해야 합니다.",
            takeoff_altitude_m=780,
            landing_altitude_m=210,
        ),
        FlyingSite(
            id=3,
            name="제주 코스탈 클리프",
            region="제주",
            difficulty="advanced",
            short_description="해안 지형 영향이 큰 숙련자 전용 사이트",
            description="해풍 변화가 빠르고 돌풍 편차가 커서 숙련자 중심으로 운영됩니다.",
            takeoff_altitude_m=420,
            landing_altitude_m=35,
        ),
        FlyingSite(
            id=4,
            name="문경 활공랜드",
            region="경북 문경",
            difficulty="intermediate",
            short_description="넓은 착륙장과 계곡풍 판단 연습에 적합한 내륙 사이트",
            description="오전에는 비교적 안정적이지만 오후에는 계곡풍이 강해질 수 있어 시간대 판단이 중요합니다.",
            takeoff_altitude_m=690,
            landing_altitude_m=160,
        ),
    ]

    rules = [
        SiteRule(
            id=1,
            site_id=1,
            allowed_direction_start=180,
            allowed_direction_end=250,
            beginner_max_average_wind=5.5,
            intermediate_max_average_wind=7.0,
            advanced_max_average_wind=8.5,
            max_gust=8.5,
            max_gust_difference=2.5,
            allow_precipitation=False,
            beginner_allowed=True,
            notes="남서풍 기준 운영, 초급 교육 비행 가능",
        ),
        SiteRule(
            id=2,
            site_id=2,
            allowed_direction_start=130,
            allowed_direction_end=210,
            beginner_max_average_wind=4.5,
            intermediate_max_average_wind=6.5,
            advanced_max_average_wind=8.0,
            max_gust=9.0,
            max_gust_difference=3.0,
            allow_precipitation=False,
            beginner_allowed=True,
            notes="오후 돌풍 점검 필요",
        ),
        SiteRule(
            id=3,
            site_id=3,
            allowed_direction_start=40,
            allowed_direction_end=110,
            beginner_max_average_wind=4.0,
            intermediate_max_average_wind=5.5,
            advanced_max_average_wind=7.0,
            max_gust=10.0,
            max_gust_difference=2.5,
            allow_precipitation=False,
            beginner_allowed=False,
            notes="숙련자 전용, 해안 돌풍 주의",
        ),
        SiteRule(
            id=4,
            site_id=4,
            allowed_direction_start=210,
            allowed_direction_end=280,
            beginner_max_average_wind=4.8,
            intermediate_max_average_wind=6.4,
            advanced_max_average_wind=7.8,
            max_gust=8.8,
            max_gust_difference=2.8,
            allow_precipitation=False,
            beginner_allowed=True,
            notes="오전 비행 적합, 오후 계곡풍 증폭 주의",
        ),
    ]

    weather_snapshots = [
        WeatherSnapshot(
            id=1,
            site_id=1,
            observed_at=now,
            average_wind_speed=4.8,
            wind_direction=215,
            gust_speed=6.4,
            precipitation_mm=0.0,
            summary="구름 조금, 이륙장 시정 양호",
            hourly_forecast=_hourly_forecast(4.8, 215, 6.4, 0.0),
        ),
        WeatherSnapshot(
            id=2,
            site_id=2,
            observed_at=now,
            average_wind_speed=5.8,
            wind_direction=165,
            gust_speed=8.1,
            precipitation_mm=0.0,
            summary="정오 이후 풍속 증가 예상",
            hourly_forecast=_hourly_forecast(5.8, 165, 8.1, 0.0),
        ),
        WeatherSnapshot(
            id=3,
            site_id=3,
            observed_at=now,
            average_wind_speed=6.9,
            wind_direction=128,
            gust_speed=11.8,
            precipitation_mm=0.6,
            summary="풍향 이탈과 약한 강수 가능성",
            hourly_forecast=_hourly_forecast(6.9, 128, 11.8, 0.6),
        ),
        WeatherSnapshot(
            id=4,
            site_id=4,
            observed_at=now,
            average_wind_speed=5.1,
            wind_direction=238,
            gust_speed=7.0,
            precipitation_mm=0.0,
            summary="오전 약한 남서풍, 시정 양호",
            hourly_forecast=_hourly_forecast(5.1, 238, 7.0, 0.0),
        ),
    ]

    notices = [
        Notice(
            id=1,
            title="주말 클럽 브리핑 시간 변경",
            body="이번 주 토요일 브리핑은 오전 8시 30분에 착륙장에서 시작합니다.",
            category="club",
            is_pinned=True,
            published_at=now - timedelta(days=1),
        ),
        Notice(
            id=2,
            title="양평 패러밸리 초급 교육 편성",
            body="초급자 1차 교육은 양평 패러밸리에서 진행되며 헬멧, 장갑, 무전기 점검이 필수입니다.",
            category="training",
            is_pinned=False,
            published_at=now - timedelta(days=2),
        ),
        Notice(
            id=3,
            title="문경 활공랜드 진입로 혼잡 안내",
            body="주말 오전에는 행사 차량이 많아 문경 활공랜드 진입 시간이 지연될 수 있습니다.",
            category="safety",
            is_pinned=False,
            published_at=now - timedelta(days=3),
        ),
    ]

    training_logs = [
        TrainingLog(
            id=1,
            user_id=2,
            site_id=1,
            training_date=date.today() - timedelta(days=7),
            training_type="이륙 반복 훈련",
            participated=True,
            flight_success=True,
            difficulty="easy",
            memo="런업과 자세 교정 중심으로 진행",
        ),
        TrainingLog(
            id=2,
            user_id=2,
            site_id=2,
            training_date=date.today() - timedelta(days=2),
            training_type="리지 판단 브리핑",
            participated=True,
            flight_success=False,
            difficulty="medium",
            memo="오후 돌풍 증가로 실제 비행은 취소",
        ),
        TrainingLog(
            id=3,
            user_id=2,
            site_id=4,
            training_date=date.today() - timedelta(days=1),
            training_type="계곡풍 판단 훈련",
            participated=True,
            flight_success=True,
            difficulty="medium",
            memo="정오 전 이륙 후 접근 패턴을 복습했습니다.",
        ),
    ]

    db.add_all(users + sites + rules + weather_snapshots + notices + training_logs)
    db.commit()

    assessments: list[FlightAssessment] = []
    rule_by_site = {rule.site_id: rule for rule in rules}
    site_by_id = {site.id: site for site in sites}
    for weather in weather_snapshots:
        site = site_by_id[weather.site_id]
        rule = rule_by_site[weather.site_id]
        for pilot_level in [PilotLevel.beginner, PilotLevel.intermediate, PilotLevel.advanced]:
            result = assess_flight(site, rule, weather, pilot_level)
            assessments.append(
                FlightAssessment(
                    site_id=site.id,
                    weather_snapshot_id=weather.id,
                    pilot_level=pilot_level.value,
                    score=result.score,
                    status=result.status,
                    reasons=result.reasons,
                    summary_text=result.summary_text,
                )
            )

    db.add_all(assessments)
    db.commit()
