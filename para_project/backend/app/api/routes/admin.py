from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.flying_site import FlyingSite
from app.models.notice import Notice
from app.models.site_rule import SiteRule
from app.schemas.notice import NoticeCreateRequest, NoticeDetailResponse, NoticeUpdateRequest
from app.schemas.site import SiteRuleResponse, SiteRuleUpsertRequest

router = APIRouter(prefix="/admin", tags=["관리자"])


@router.get("/site-rules/{site_id}", response_model=SiteRuleResponse)
def read_site_rule(site_id: int, db: Session = Depends(get_db)) -> SiteRuleResponse:
    site = db.get(FlyingSite, site_id)
    if site is None or site.rule is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="사이트 기준 정보를 찾을 수 없습니다.")
    return SiteRuleResponse.model_validate(site.rule)


@router.post("/site-rules", response_model=SiteRuleResponse, status_code=status.HTTP_201_CREATED)
def create_site_rule(payload: SiteRuleUpsertRequest, db: Session = Depends(get_db)) -> SiteRuleResponse:
    site = db.get(FlyingSite, payload.site_id)
    if site is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="사이트를 찾을 수 없습니다.")
    if site.rule is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="이미 기준 정보가 존재합니다.")

    rule = SiteRule(**payload.model_dump())
    db.add(rule)
    db.commit()
    db.refresh(rule)
    return SiteRuleResponse.model_validate(rule)


@router.put("/site-rules/{site_id}", response_model=SiteRuleResponse)
def update_site_rule(
    site_id: int,
    payload: SiteRuleUpsertRequest,
    db: Session = Depends(get_db),
) -> SiteRuleResponse:
    if site_id != payload.site_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="site_id가 일치하지 않습니다.")

    site = db.get(FlyingSite, site_id)
    if site is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="사이트를 찾을 수 없습니다.")

    rule = site.rule
    if rule is None:
        rule = SiteRule(**payload.model_dump())
        db.add(rule)
    else:
        for key, value in payload.model_dump().items():
            setattr(rule, key, value)

    db.commit()
    db.refresh(rule)
    return SiteRuleResponse.model_validate(rule)


@router.post("/notices", response_model=NoticeDetailResponse, status_code=status.HTTP_201_CREATED)
def create_notice(payload: NoticeCreateRequest, db: Session = Depends(get_db)) -> NoticeDetailResponse:
    notice = Notice(**payload.model_dump())
    db.add(notice)
    db.commit()
    db.refresh(notice)
    return NoticeDetailResponse.model_validate(notice)


@router.put("/notices/{notice_id}", response_model=NoticeDetailResponse)
def update_notice(
    notice_id: int,
    payload: NoticeUpdateRequest,
    db: Session = Depends(get_db),
) -> NoticeDetailResponse:
    notice = db.get(Notice, notice_id)
    if notice is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="공지를 찾을 수 없습니다.")

    for key, value in payload.model_dump().items():
        setattr(notice, key, value)

    db.commit()
    db.refresh(notice)
    return NoticeDetailResponse.model_validate(notice)
