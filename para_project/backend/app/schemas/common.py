from datetime import datetime

from pydantic import BaseModel


class AssessmentResponse(BaseModel):
    score: int
    status: str
    reasons: list[str]
    summary_text: str


class HourlyForecastResponse(BaseModel):
    time_label: str
    average_wind_speed: float
    wind_direction: int
    gust_speed: float
    precipitation_mm: float | None = None


class WeatherSnapshotResponse(BaseModel):
    observed_at: datetime
    average_wind_speed: float
    wind_direction: int
    gust_speed: float
    precipitation_mm: float | None = None
    summary: str
    hourly_forecast: list[HourlyForecastResponse]
