from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.db.session import get_db
from app.models.enums import PilotLevel
from app.models.flying_site import FlyingSite
from app.schemas.common import AssessmentResponse
from app.services.assessment import assess_flight, latest_weather_for_site

router = APIRouter(prefix="/assessments", tags=["비행 판단"])


@router.get("/sites/{site_id}", response_model=AssessmentResponse)
def read_assessment(
    site_id: int,
    pilot_level: PilotLevel = Query(default=PilotLevel.beginner),
    db: Session = Depends(get_db),
) -> AssessmentResponse:
    site = (
        db.execute(
            select(FlyingSite)
            .where(FlyingSite.id == site_id)
            .options(
                selectinload(FlyingSite.rule),
                selectinload(FlyingSite.weather_snapshots),
            )
        )
        .scalar_one_or_none()
    )
    if site is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="사이트를 찾을 수 없습니다.")
    if site.rule is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="사이트 기준 정보가 없습니다.")

    weather = latest_weather_for_site(site)
    if weather is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="기상 정보가 없습니다.")

    return assess_flight(site, site.rule, weather, pilot_level)
