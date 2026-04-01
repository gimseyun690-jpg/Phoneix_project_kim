from __future__ import annotations

import argparse
import html
import io
import json
import re
import urllib.request
import zipfile
from dataclasses import dataclass
from html.parser import HTMLParser
from pathlib import Path
from typing import Iterable
from xml.etree import ElementTree as ET

KML_NS = {'k': 'http://www.opengis.net/kml/2.2'}


class _LineHtmlParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() == 'br':
            self.parts.append('\n')

    def handle_data(self, data: str) -> None:
        self.parts.append(data)


@dataclass(frozen=True)
class ImportedSiteRecord:
    source_id: str
    order: int
    name: str
    region_hint: str
    latitude: float
    longitude: float
    site_type: str
    summary_line: str
    description_text: str
    wind_note: str | None
    image_url: str | None
    windguru_url: str | None
    windy_url: str | None
    kma_forecast_url: str | None
    aws_observation_url: str | None
    station_label: str | None
    folder_name: str
    style_id: str

    def to_json(self) -> dict[str, object]:
        return {
            'source_id': self.source_id,
            'order': self.order,
            'name': self.name,
            'region_hint': self.region_hint,
            'latitude': self.latitude,
            'longitude': self.longitude,
            'site_type': self.site_type,
            'summary_line': self.summary_line,
            'description_text': self.description_text,
            'wind_note': self.wind_note,
            'image_url': self.image_url,
            'windguru_url': self.windguru_url,
            'windy_url': self.windy_url,
            'kma_forecast_url': self.kma_forecast_url,
            'aws_observation_url': self.aws_observation_url,
            'station_label': self.station_label,
            'folder_name': self.folder_name,
            'style_id': self.style_id,
        }


def _read_remote_or_embedded_kml(input_path: Path) -> bytes:
    raw = input_path.read_bytes()
    kml_bytes = _extract_kml_bytes(raw)
    root = ET.fromstring(kml_bytes)
    if _count_point_placemarks(root) > 0:
        return kml_bytes

    href = root.findtext('.//k:NetworkLink/k:Link/k:href', default='', namespaces=KML_NS).strip()
    if not href:
        return kml_bytes

    with urllib.request.urlopen(href) as response:
        remote_bytes = response.read()
    return _extract_kml_bytes(remote_bytes)


def _extract_kml_bytes(raw: bytes) -> bytes:
    if zipfile.is_zipfile(io.BytesIO(raw)):
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            for name in archive.namelist():
                if name.lower().endswith('.kml'):
                    return archive.read(name)
        raise ValueError('KMZ 안에서 KML 파일을 찾지 못했습니다.')
    return raw


def _count_point_placemarks(root: ET.Element) -> int:
    return len(root.findall('.//k:Placemark[k:Point]', KML_NS))


def _iter_placemarks(node: ET.Element, folder_name: str = '') -> Iterable[tuple[ET.Element, str]]:
    for child in node:
        tag = child.tag.rsplit('}', 1)[-1]
        if tag == 'Folder':
            next_folder = child.findtext('k:name', default=folder_name, namespaces=KML_NS).strip() or folder_name
            yield from _iter_placemarks(child, next_folder)
        elif tag == 'Document':
            yield from _iter_placemarks(child, folder_name)
        elif tag == 'Placemark':
            yield child, folder_name


def _split_description_lines(description_html: str) -> list[str]:
    parser = _LineHtmlParser()
    parser.feed(description_html)
    plain_text = html.unescape(''.join(parser.parts)).replace('\xa0', ' ')
    lines = [' '.join(line.split()) for line in plain_text.splitlines()]
    return [line for line in lines if line]


def _extract_site_type(name: str) -> str:
    if '착륙장' in name:
        return 'landing'
    if '연습장' in name or '수련원' in name:
        return 'practice'
    if '이륙장' in name:
        return 'takeoff'
    return 'site'


def _extract_first_url(text: str, keyword: str) -> str | None:
    for url in re.findall(r"https?://[^\s<>\"')]+", text):
        if keyword in url:
            return url
    return None


def _extract_station_label(lines: list[str]) -> str | None:
    for line in lines:
        if '실시간 관측자료' in line or '기상청' in line:
            cleaned = re.sub(r'https?://\S+', '', line).strip()
            if ' - ' in cleaned:
                return cleaned.split(' - ', 1)[0].strip() or None
            return cleaned or None
    return None


def _normalize_text_line(line: str) -> str:
    cleaned = re.sub(r'https?://\S+', '', line)
    cleaned = cleaned.replace('()', '')
    cleaned = cleaned.strip(' -()')
    cleaned = ' '.join(cleaned.split())
    if re.fullmatch(r'[a-zA-Z0-9_]+=.*', cleaned):
        return ''
    if cleaned.startswith('www.') or cleaned.startswith('http'):
        return ''
    return cleaned


def _extract_region_hint(name: str, summary_line: str) -> str:
    if not summary_line:
        return ''
    if name in summary_line:
        prefix = summary_line.split(name, 1)[0].strip(' -')
        return prefix
    return ''


def _extract_wind_note(summary_line: str) -> str | None:
    if ' - ' not in summary_line:
        return None
    note = summary_line.split(' - ', 1)[1]
    note = re.split(r'https?://|\(', note, maxsplit=1)[0]
    note = note.strip(' -')
    return note or None


def _extract_image_url(description_html: str) -> str | None:
    match = re.search(r'<img[^>]+src="([^"]+)"', description_html, flags=re.IGNORECASE)
    return match.group(1) if match else None


def build_records(kml_bytes: bytes) -> list[ImportedSiteRecord]:
    root = ET.fromstring(kml_bytes)
    records: list[ImportedSiteRecord] = []
    order = 0

    for placemark, folder_name in _iter_placemarks(root):
        coords = placemark.findtext('.//k:Point/k:coordinates', default='', namespaces=KML_NS).strip()
        if not coords:
            continue
        coord_parts = [part.strip() for part in coords.split(',')]
        if len(coord_parts) < 2:
            continue

        name = placemark.findtext('k:name', default='', namespaces=KML_NS).strip()
        if not name:
            continue

        longitude = float(coord_parts[0])
        latitude = float(coord_parts[1])
        description_html = placemark.findtext('k:description', default='', namespaces=KML_NS)
        lines = _split_description_lines(description_html)
        normalized_lines = [_normalize_text_line(line) for line in lines]
        normalized_lines = [line for line in normalized_lines if line]

        summary_line = next((line for line in normalized_lines if name in line), normalized_lines[0] if normalized_lines else name)
        region_hint = _extract_region_hint(name, summary_line)
        wind_note = _extract_wind_note(summary_line)
        description_lines = []
        for line in normalized_lines:
            if line not in description_lines:
                description_lines.append(line)

        description_text = '\n'.join(description_lines[:5]) or name
        style_url = placemark.findtext('k:styleUrl', default='', namespaces=KML_NS).strip().lstrip('#')

        records.append(
            ImportedSiteRecord(
                source_id=f'kmz-site-{order + 1:03d}',
                order=order,
                name=name,
                region_hint=region_hint,
                latitude=latitude,
                longitude=longitude,
                site_type=_extract_site_type(name),
                summary_line=summary_line,
                description_text=description_text,
                wind_note=wind_note,
                image_url=_extract_image_url(description_html),
                windguru_url=_extract_first_url(description_html, 'windguru'),
                windy_url=_extract_first_url(description_html, 'windy.com'),
                kma_forecast_url=_extract_first_url(description_html, 'kma.go.kr'),
                aws_observation_url=_extract_first_url(description_html, 'nph-aws_txt_min'),
                station_label=_extract_station_label(normalized_lines),
                folder_name=folder_name,
                style_id=style_url,
            ),
        )
        order += 1

    return records


def main() -> None:
    parser = argparse.ArgumentParser(description='KMZ 전국 활공장 데이터를 앱용 JSON으로 변환합니다.')
    parser.add_argument('input', help='입력 KMZ 또는 KML 경로')
    parser.add_argument('output', help='출력 JSON 경로')
    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)

    kml_bytes = _read_remote_or_embedded_kml(input_path)
    records = build_records(kml_bytes)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps([record.to_json() for record in records], ensure_ascii=False, indent=2),
        encoding='utf-8',
    )
    print(f'활공장 {len(records)}개를 {output_path}로 저장했습니다.')


if __name__ == '__main__':
    main()
