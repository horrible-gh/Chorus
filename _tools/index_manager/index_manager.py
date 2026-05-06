#!/usr/bin/env python3
"""index_manager.py — INDEX.md 관리 도구"""

import argparse
import re
import sys
from collections import defaultdict
from datetime import date
from pathlib import Path

# Ensure UTF-8 output on Windows
sys.stdout.reconfigure(encoding='utf-8')
sys.stderr.reconfigure(encoding='utf-8')

# ── 프로젝트 설정 ─────────────────────────────────────────────────────────────
PROJECTS = {
    "chorus": {
        "index_path": Path(r"C:\workspace\projects\Documents\projects\Chorus\INDEX.md"),
        "archive_type": "dated_file",
        "archive_dir": Path(r"C:\workspace\projects\Documents\projects\Chorus\980_archive"),
        "section": "## 현재 기표 항목",
        # 컬럼 순서: ID(0), 항목(1), 난이도(2), 상태(3), 메모(4)
        "col_status": 3,
        "col_memo": 4,
        "id_backtick": False,
    },
    "flowgate": {
        "index_path": Path(r"C:\workspace\projects\Documents\projects\FlowGate\INDEX.md"),
        "archive_type": "single_file",
        "archive_path": Path(r"C:\workspace\projects\Documents\projects\FlowGate\98_archive\INDEX.md"),
        "section": "## 현재 기표 항목",
        # 컬럼 순서: ID(0), 항목(1), 상태(2), 메모(3)
        "col_status": 2,
        "col_memo": 3,
        "id_backtick": True,
    },
}


# ── 마크다운 테이블 파싱 유틸 ─────────────────────────────────────────────────

def parse_row(line: str) -> list:
    """마크다운 테이블 행 → 셀 목록 (스트립 처리)"""
    parts = line.split("|")
    if parts and parts[0].strip() == "":
        parts = parts[1:]
    if parts and parts[-1].strip() == "":
        parts = parts[:-1]
    return [p.strip() for p in parts]


def is_separator_row(line: str) -> bool:
    """구분자 행 여부 (예: |---|---|---|)"""
    if not line.strip().startswith("|"):
        return False
    cells = parse_row(line)
    return bool(cells) and all(re.match(r"^-+$", c) for c in cells)


def is_table_row(line: str) -> bool:
    return line.strip().startswith("|")


def cells_to_row(cells: list) -> str:
    return "| " + " | ".join(cells) + " |\n"


def normalize_id(id_str: str) -> str:
    """ID 비교용 정규화 (백틱 제거)"""
    return id_str.strip().strip("`")


def find_table_in_section(lines: list, section: str):
    """
    섹션 내 첫 번째 테이블 범위 반환.
    반환값: (header_idx, sep_idx, data_start, data_end) 또는 None
    data_end: 마지막 데이터 행 다음 인덱스 (slice 기준)
    """
    section_idx = None
    for i, line in enumerate(lines):
        if line.rstrip() == section:
            section_idx = i
            break
    if section_idx is None:
        return None

    header_idx = None
    for i in range(section_idx + 1, len(lines)):
        stripped = lines[i].strip()
        if is_table_row(lines[i]):
            header_idx = i
            break
        if stripped.startswith("## ") and i != section_idx:
            break

    if header_idx is None:
        return None

    sep_idx = header_idx + 1
    if sep_idx >= len(lines) or not is_separator_row(lines[sep_idx]):
        return None

    data_start = sep_idx + 1
    data_end = data_start
    for i in range(data_start, len(lines)):
        if is_table_row(lines[i]):
            data_end = i + 1
        else:
            break

    return header_idx, sep_idx, data_start, data_end


def get_data_rows(lines: list, data_start: int, data_end: int) -> list:
    """(행 인덱스, 파싱된 셀 목록) 목록 반환"""
    result = []
    for i in range(data_start, data_end):
        if is_table_row(lines[i]):
            result.append((i, parse_row(lines[i])))
    return result


def read_index(path: Path) -> list:
    return path.read_text(encoding="utf-8").splitlines(keepends=True)


def write_index(path: Path, lines: list):
    path.write_text("".join(lines), encoding="utf-8")


# ── 명령 함수들 ────────────────────────────────────────────────────────────────

def cmd_open(project: str, cfg: dict, item_id: str, title: str):
    """미등록 항목을 INDEX에 추가 (상태=Open)"""
    lines = read_index(cfg["index_path"])
    info = find_table_in_section(lines, cfg["section"])
    if info is None:
        print(f"[오류] '{cfg['section']}' 섹션의 테이블을 찾을 수 없습니다.")
        sys.exit(1)

    header_idx, sep_idx, data_start, data_end = info
    rows = get_data_rows(lines, data_start, data_end)

    for _, cells in rows:
        if cells and normalize_id(cells[0]) == item_id:
            print(f"[오류] ID '{item_id}'는 이미 등록되어 있습니다.")
            sys.exit(1)

    formatted_id = f"`{item_id}`" if cfg["id_backtick"] else item_id

    if project == "chorus":
        new_cells = [formatted_id, title, "-", "Open", ""]
    else:
        new_cells = [formatted_id, title, "Open", ""]

    lines.insert(data_end, cells_to_row(new_cells))
    write_index(cfg["index_path"], lines)
    print(f"[추가] {item_id}: {title} → Open")


def cmd_change_status(cfg: dict, item_id: str, new_status: str):
    """항목 상태 변경 (운영메모 컬럼 보존)"""
    lines = read_index(cfg["index_path"])
    info = find_table_in_section(lines, cfg["section"])
    if info is None:
        print("[오류] 테이블을 찾을 수 없습니다.")
        sys.exit(1)

    _, _, data_start, data_end = info
    rows = get_data_rows(lines, data_start, data_end)

    for row_idx, cells in rows:
        if cells and normalize_id(cells[0]) == item_id:
            new_cells = list(cells)
            new_cells[cfg["col_status"]] = new_status
            lines[row_idx] = cells_to_row(new_cells)
            write_index(cfg["index_path"], lines)
            print(f"[상태 변경] {item_id} → {new_status}")
            return

    print(f"[오류] ID '{item_id}'를 찾을 수 없습니다.")
    sys.exit(1)


def cmd_archive_chorus(cfg: dict):
    """Chorus: Closed 항목을 날짜별 아카이브 파일로 이동 후 INDEX에서 제거"""
    lines = read_index(cfg["index_path"])
    info = find_table_in_section(lines, cfg["section"])
    if info is None:
        print("[오류] 테이블을 찾을 수 없습니다.")
        sys.exit(1)

    header_idx, sep_idx, data_start, data_end = info
    rows = get_data_rows(lines, data_start, data_end)
    closed_rows = [(idx, cells) for idx, cells in rows
                   if cells and cells[cfg["col_status"]] == "Closed"]

    if not closed_rows:
        print("[정보] Closed 항목이 없습니다.")
        return

    today = date.today().strftime("%Y-%m-%d")
    archive_file = cfg["archive_dir"] / f"INDEX_archive_{today}.md"

    if archive_file.exists():
        arch_lines = archive_file.read_text(encoding="utf-8").splitlines(keepends=True)
        arch_info = find_table_in_section(arch_lines, "## 추출된 Closed 항목")
        if arch_info:
            _, _, _, arch_data_end = arch_info
            for _, cells in closed_rows:
                arch_lines.insert(arch_data_end, cells_to_row(cells))
                arch_data_end += 1
            archive_file.write_text("".join(arch_lines), encoding="utf-8")
        else:
            with archive_file.open("a", encoding="utf-8") as f:
                for _, cells in closed_rows:
                    f.write(cells_to_row(cells))
    else:
        header_line = lines[header_idx]
        sep_line = lines[sep_idx]
        content = (
            f"# INDEX Archive — {today}\n\n"
            f"원본: ../INDEX.md\n\n"
            f"## 추출된 Closed 항목\n\n"
            f"{header_line}"
            f"{sep_line}"
        )
        for _, cells in closed_rows:
            content += cells_to_row(cells)
        archive_file.write_text(content, encoding="utf-8")

    for row_idx, _ in reversed(closed_rows):
        del lines[row_idx]

    write_index(cfg["index_path"], lines)
    print(f"[아카이브] {len(closed_rows)}개 항목 → {archive_file.name}")
    for _, cells in closed_rows:
        print(f"  - {cells[0]}: {cells[1]}")


def cmd_archive_flowgate(cfg: dict):
    """FlowGate: Closed 항목을 단일 아카이브 파일에 날짜 컬럼과 함께 누적"""
    lines = read_index(cfg["index_path"])
    info = find_table_in_section(lines, cfg["section"])
    if info is None:
        print("[오류] 테이블을 찾을 수 없습니다.")
        sys.exit(1)

    _, _, data_start, data_end = info
    rows = get_data_rows(lines, data_start, data_end)
    closed_rows = [(idx, cells) for idx, cells in rows
                   if cells and cells[cfg["col_status"]] == "Closed"]

    if not closed_rows:
        print("[정보] Closed 항목이 없습니다.")
        return

    today = date.today().strftime("%Y-%m-%d")
    archive_path = cfg["archive_path"]

    arch_lines = archive_path.read_text(encoding="utf-8").splitlines(keepends=True)
    arch_info = find_table_in_section(arch_lines, "## 아카이브 항목")
    if arch_info is None:
        print("[오류] 아카이브 파일에서 '## 아카이브 항목' 섹션을 찾을 수 없습니다.")
        sys.exit(1)

    _, _, _, arch_data_end = arch_info

    # 아카이브 컬럼: | ID | 항목 | 상태 | 아카이브 일자 | 이관 파일 | 메모 |
    for _, cells in closed_rows:
        item_id = cells[0]
        title = cells[1]
        status = cells[cfg["col_status"]]
        memo = cells[cfg["col_memo"]] if cfg["col_memo"] < len(cells) else ""
        arch_cells = [item_id, title, status, today, "-", memo]
        arch_lines.insert(arch_data_end, cells_to_row(arch_cells))
        arch_data_end += 1

    archive_path.write_text("".join(arch_lines), encoding="utf-8")

    for row_idx, _ in reversed(closed_rows):
        del lines[row_idx]

    write_index(cfg["index_path"], lines)
    print(f"[아카이브] {len(closed_rows)}개 항목 → {archive_path.name}")
    for _, cells in closed_rows:
        print(f"  - {cells[0]}: {cells[1]}")


def cmd_status(cfg: dict):
    """전체 항목 현황 출력"""
    lines = read_index(cfg["index_path"])
    info = find_table_in_section(lines, cfg["section"])
    if info is None:
        print("[오류] 테이블을 찾을 수 없습니다.")
        sys.exit(1)

    _, _, data_start, data_end = info
    rows = get_data_rows(lines, data_start, data_end)

    by_status = defaultdict(list)
    for _, cells in rows:
        if cells:
            status = cells[cfg["col_status"]] if cfg["col_status"] < len(cells) else "?"
            by_status[status].append(cells)

    print(f"[현황] 총 {len(rows)}개 항목")
    status_order = ["Open", "Reopened", "Monitoring", "Done", "Closed"]
    for status in status_order:
        items = by_status.get(status, [])
        if items:
            print(f"\n  {status} ({len(items)})")
            for cells in items:
                print(f"    {normalize_id(cells[0])}: {cells[1]}")

    for status, items in by_status.items():
        if status not in status_order:
            print(f"\n  {status} ({len(items)})")
            for cells in items:
                print(f"    {normalize_id(cells[0])}: {cells[1]}")


# ── 진입점 ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="INDEX.md 관리 도구",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
사용 예시:
  python index_manager.py --project chorus status
  python index_manager.py --project chorus close T005
  python index_manager.py --project chorus archive
  python index_manager.py --project flowgate open T022 "새 태스크 제목"
  python index_manager.py --project flowgate monitoring T013
  python index_manager.py --project flowgate reopen T013
        """,
    )
    parser.add_argument("--project", required=True, choices=list(PROJECTS.keys()),
                        help="프로젝트 선택")
    parser.add_argument("command",
                        choices=["open", "monitoring", "close", "archive", "reopen", "status"],
                        help="실행할 명령")
    parser.add_argument("args", nargs="*", help="명령 인자 (ID, 제목 등)")

    parsed = parser.parse_args()
    cfg = PROJECTS[parsed.project]

    if parsed.command == "open":
        if len(parsed.args) < 2:
            print("[오류] open 명령에는 ID와 제목이 필요합니다.")
            print("  사용법: python index_manager.py --project <project> open <ID> <제목>")
            sys.exit(1)
        cmd_open(parsed.project, cfg, parsed.args[0], parsed.args[1])

    elif parsed.command == "monitoring":
        if not parsed.args:
            print("[오류] monitoring 명령에는 ID가 필요합니다.")
            sys.exit(1)
        cmd_change_status(cfg, parsed.args[0], "Monitoring")

    elif parsed.command == "close":
        if not parsed.args:
            print("[오류] close 명령에는 ID가 필요합니다.")
            sys.exit(1)
        cmd_change_status(cfg, parsed.args[0], "Closed")

    elif parsed.command == "reopen":
        if not parsed.args:
            print("[오류] reopen 명령에는 ID가 필요합니다.")
            sys.exit(1)
        cmd_change_status(cfg, parsed.args[0], "Open")

    elif parsed.command == "archive":
        if parsed.project == "chorus":
            cmd_archive_chorus(cfg)
        else:
            cmd_archive_flowgate(cfg)

    elif parsed.command == "status":
        cmd_status(cfg)


if __name__ == "__main__":
    main()
