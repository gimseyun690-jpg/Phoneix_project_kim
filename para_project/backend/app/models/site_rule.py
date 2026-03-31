from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class SiteRule(Base):
    __tablename__ = "site_rules"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    site_id: Mapped[int] = mapped_column(ForeignKey("flying_sites.id"), unique=True, index=True)
    allowed_direction_start: Mapped[int] = mapped_column(Integer)
    allowed_direction_end: Mapped[int] = mapped_column(Integer)
    beginner_max_average_wind: Mapped[float] = mapped_column(Float)
    intermediate_max_average_wind: Mapped[float] = mapped_column(Float)
    advanced_max_average_wind: Mapped[float] = mapped_column(Float)
    max_gust: Mapped[float] = mapped_column(Float)
    max_gust_difference: Mapped[float] = mapped_column(Float)
    allow_precipitation: Mapped[bool] = mapped_column(Boolean, default=False)
    beginner_allowed: Mapped[bool] = mapped_column(Boolean, default=True)
    notes: Mapped[str] = mapped_column(String(255), default="")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    site: Mapped["FlyingSite"] = relationship(back_populates="rule")
