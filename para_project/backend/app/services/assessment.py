from __future__ import annotations

from app.models.enums import FlightStatus, PilotLevel
from app.models.flying_site import FlyingSite
from app.models.site_rule import SiteRule
from app.models.weather_snapshot import WeatherSnapshot
from app.schemas.common import AssessmentResponse, HourlyForecastResponse, WeatherSnapshotResponse
from app.schemas.site import SiteDetailResponse, SiteRuleResponse, SiteSummaryResponse


def _angle_in_range(angle: int, start: int, end: int) -> bool:
    normalized_angle = angle % 360
    normalized_start = start % 360
    normalized_end = end % 360

    if normalized_start <= normalized_end:
        return normalized_start <= normalized_angle <= normalized_end
    return normalized_angle >= normalized_start or normalized_angle <= normalized_end


def _max_average_wind_for_level(rule: SiteRule, pilot_level: PilotLevel) -> float:
    if pilot_level == PilotLevel.beginner:
        return rule.beginner_max_average_wind
    if pilot_level == PilotLevel.intermediate:
        return rule.intermediate_max_average_wind
    return rule.advanced_max_average_wind


def _pilot_level_label(pilot_level: PilotLevel) -> str:
    if pilot_level == PilotLevel.beginner:
        return "초급"
    if pilot_level == PilotLevel.intermediate:
        return "중급"
    return "숙련"


def latest_weather_for_site(site: FlyingSite) -> WeatherSnapshot | None:
    if not site.weather_snapshots:
        return None
    return max(site.weather_snapshots, key=lambda item: item.observed_at)


def assess_flight(
    site: FlyingSite,
    rule: SiteRule,
    weather: WeatherSnapshot,
    pilot_level: PilotLevel,
) -> AssessmentResponse:
    score = 100
    reasons: list[str] = []

    if pilot_level == PilotLevel.beginner and not rule.beginner_allowed:
        score -= 45
        reasons.append("초급자 비행이 허용되지 않는 사이트입니다.")

    if not _angle_in_range(weather.wind_direction, rule.allowed_direction_start, rule.allowed_direction_end):
        score -= 25
        reasons.append(
            f"현재 풍향 {weather.wind_direction}도가 허용 범위 "
            f"{rule.allowed_direction_start}-{rule.allowed_direction_end}도 밖입니다."
        )

    max_average_wind = _max_average_wind_for_level(rule, pilot_level)
    if weather.average_wind_speed > max_average_wind:
        wind_over = weather.average_wind_speed - max_average_wind
        score -= min(35, 20 + int(round(wind_over * 8)))
        reasons.append(
            f"평균 풍속 {weather.average_wind_speed:.1f}m/s가 "
            f"{_pilot_level_label(pilot_level)} 기준 {max_average_wind:.1f}m/s를 초과합니다."
        )

    if weather.gust_speed > rule.max_gust:
        gust_over = weather.gust_speed - rule.max_gust
        score -= min(25, 15 + int(round(gust_over * 5)))
        reasons.append(
            f"최대 돌풍 {weather.gust_speed:.1f}m/s가 허용치 {rule.max_gust:.1f}m/s를 초과합니다."
        )

    gust_difference = weather.gust_speed - weather.average_wind_speed
    if gust_difference > rule.max_gust_difference:
        diff_over = gust_difference - rule.max_gust_difference
        score -= min(20, 10 + int(round(diff_over * 6)))
        reasons.append(
            f"돌풍 편차 {gust_difference:.1f}m/s가 허용 편차 {rule.max_gust_difference:.1f}m/s를 초과합니다."
        )

    precipitation = weather.precipitation_mm or 0.0
    if precipitation > 0 and not rule.allow_precipitation:
        score -= min(20, 15 + int(round(precipitation * 5)))
        reasons.append("강수 가능성이 있어 비행을 권장하지 않습니다.")

    if not reasons:
        reasons.append("주요 비행 기준을 모두 충족합니다.")

    score = max(0, int(score))
    if score >= 80:
        status = FlightStatus.good.value
        summary_text = "현재 기준으로는 비행 여건이 양호합니다."
    elif score >= 60:
        status = FlightStatus.caution.value
        summary_text = "일부 조건이 한계에 가까워 주의가 필요합니다."
    else:
        status = FlightStatus.bad.value
        summary_text = "안전 기준을 충족하지 않아 비행 비추천입니다."

    return AssessmentResponse(
        score=score,
        status=status,
        reasons=reasons,
        summary_text=summary_text,
    )


def to_weather_response(weather: WeatherSnapshot) -> WeatherSnapshotResponse:
    return WeatherSnapshotResponse(
        observed_at=weather.observed_at,
        average_wind_speed=weather.average_wind_speed,
        wind_direction=weather.wind_direction,
        gust_speed=weather.gust_speed,
        precipitation_mm=weather.precipitation_mm,
        summary=weather.summary,
        hourly_forecast=[HourlyForecastResponse(**item) for item in weather.hourly_forecast],
    )


def build_site_summary(
    site: FlyingSite,
    weather: WeatherSnapshot,
    assessment: AssessmentResponse,
) -> SiteSummaryResponse:
    return SiteSummaryResponse(
        id=site.id,
        name=site.name,
        region=site.region,
        difficulty=site.difficulty,
        short_description=site.short_description,
        beginner_allowed=site.rule.beginner_allowed if site.rule else False,
        weather=to_weather_response(weather),
        assessment=assessment,
    )


def build_site_detail(
    site: FlyingSite,
    weather: WeatherSnapshot,
    assessment: AssessmentResponse,
) -> SiteDetailResponse:
    return SiteDetailResponse(
        **build_site_summary(site, weather, assessment).model_dump(),
        description=site.description,
        takeoff_altitude_m=site.takeoff_altitude_m,
        landing_altitude_m=site.landing_altitude_m,
        allowed_direction_range=f"{site.rule.allowed_direction_start}-{site.rule.allowed_direction_end}도",
        rule=SiteRuleResponse.model_validate(site.rule),
    )
