from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import Boolean, DateTime, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class FlyingSite(Base):
    __tablename__ = "flying_sites"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(120), unique=True, index=True)
    region: Mapped[str] = mapped_column(String(120), index=True)
    difficulty: Mapped[str] = mapped_column(String(32))
    short_description: Mapped[str] = mapped_column(String(255))
    description: Mapped[str] = mapped_column(Text)
    takeoff_altitude_m: Mapped[int] = mapped_column(Integer)
    landing_altitude_m: Mapped[int] = mapped_column(Integer)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
    )

    rule: Mapped["SiteRule | None"] = relationship(back_populates="site", uselist=False)
    weather_snapshots: Mapped[list["WeatherSnapshot"]] = relationship(back_populates="site")
    assessments: Mapped[list["FlightAssessment"]] = relationship(back_populates="site")
    training_logs: Mapped[list["TrainingLog"]] = relationship(back_populates="site")
