from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.db.session import get_db
from app.models.flying_site import FlyingSite
from app.models.training_log import TrainingLog
from app.models.user import User
from app.schemas.training_log import TrainingLogCreateRequest, TrainingLogResponse

router = APIRouter(prefix="/training-logs", tags=["훈련 기록"])


@router.get("", response_model=list[TrainingLogResponse])
def list_training_logs(
    user_id: int = Query(default=2),
    db: Session = Depends(get_db),
) -> list[TrainingLogResponse]:
    logs = (
        db.execute(
            select(TrainingLog)
            .where(TrainingLog.user_id == user_id)
            .options(selectinload(TrainingLog.site))
            .order_by(TrainingLog.training_date.desc(), TrainingLog.id.desc())
        )
        .scalars()
        .all()
    )
    return [TrainingLogResponse.from_model(log) for log in logs]


@router.post("", response_model=TrainingLogResponse, status_code=status.HTTP_201_CREATED)
def create_training_log(
    payload: TrainingLogCreateRequest,
    db: Session = Depends(get_db),
) -> TrainingLogResponse:
    user = db.get(User, payload.user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="사용자를 찾을 수 없습니다.")

    site = db.get(FlyingSite, payload.site_id)
    if site is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="사이트를 찾을 수 없습니다.")

    log = TrainingLog(**payload.model_dump())
    db.add(log)
    db.commit()
    db.refresh(log)
    log.site = site
    return TrainingLogResponse.from_model(log)
