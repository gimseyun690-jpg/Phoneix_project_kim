from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.db.session import get_db
from app.models.flying_site import FlyingSite
from app.schemas.common import WeatherSnapshotResponse
from app.services.assessment import latest_weather_for_site, to_weather_response

router = APIRouter(prefix="/weather", tags=["기상"])


@router.get("/sites/{site_id}/latest", response_model=WeatherSnapshotResponse)
def read_latest_weather(site_id: int, db: Session = Depends(get_db)) -> WeatherSnapshotResponse:
    site = (
        db.execute(
            select(FlyingSite)
            .where(FlyingSite.id == site_id)
            .options(selectinload(FlyingSite.weather_snapshots))
        )
        .scalar_one_or_none()
    )
    if site is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="사이트를 찾을 수 없습니다.")

    weather = latest_weather_for_site(site)
    if weather is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="기상 정보가 없습니다.")

    return to_weather_response(weather)
