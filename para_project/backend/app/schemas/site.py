from pydantic import BaseModel, ConfigDict

from app.schemas.common import AssessmentResponse, WeatherSnapshotResponse


class SiteRuleUpsertRequest(BaseModel):
    site_id: int
    allowed_direction_start: int
    allowed_direction_end: int
    beginner_max_average_wind: float
    intermediate_max_average_wind: float
    advanced_max_average_wind: float
    max_gust: float
    max_gust_difference: float
    allow_precipitation: bool = False
    beginner_allowed: bool = True
    notes: str = ""


class SiteRuleResponse(SiteRuleUpsertRequest):
    id: int

    model_config = ConfigDict(from_attributes=True)


class SiteSummaryResponse(BaseModel):
    id: int
    name: str
    region: str
    difficulty: str
    short_description: str
    beginner_allowed: bool
    weather: WeatherSnapshotResponse
    assessment: AssessmentResponse


class SiteDetailResponse(SiteSummaryResponse):
    description: str
    takeoff_altitude_m: int
    landing_altitude_m: int
    allowed_direction_range: str
    rule: SiteRuleResponse
