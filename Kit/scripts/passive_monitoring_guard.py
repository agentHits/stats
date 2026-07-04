#!/usr/bin/env python3

import os
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCAN_ROOTS = ("Modules", "Kit")
SKIP_PARTS = {
    ".build",
    ".git",
    ".agent-work",
    "build",
    "DerivedData",
    "Pods",
    "xcloc",
    "xcarchive",
}
SKIP_FILES = {
    Path("Kit/plugins/DB.swift"),
    Path("Kit/plugins/Store.swift"),
    Path("Kit/plugins/Logger.swift"),
    Path("Kit/plugins/SystemStats.swift"),
    Path("Kit/plugins/Updater.swift"),
}

HISTORY_TYPE_RE = re.compile(
    r"\b(?:public\s+|private\s+|internal\s+|open\s+|final\s+|fileprivate\s+)*"
    r"(?:final\s+)?(?:class|struct|actor)\s+"
    r"(?P<name>[A-Za-z_][A-Za-z0-9_]*)"
)
HISTORY_EXTENSION_RE = re.compile(
    r"\bextension\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)"
)
HISTORY_NAME_RE = re.compile(r"(?:ActivityHistory|RuntimeHistory|HistoryStore|HistorySnapshot)")

FORBIDDEN_PATTERNS = [
    ("DB.shared", re.compile(r"\bDB\.shared\b")),
    ("JSONEncoder", re.compile(r"\bJSONEncoder\s*\(")),
    ("JSONDecoder", re.compile(r"\bJSONDecoder\s*\(")),
    ("FileManager.default", re.compile(r"\bFileManager\.default\b")),
    ("createDirectory", re.compile(r"\bcreateDirectory\s*\(")),
    ("createFile", re.compile(r"\bcreateFile\s*\(")),
    ("write(to:)", re.compile(r"\.write\s*\(\s*to\s*:")),
    ("FileHandle", re.compile(r"\bFileHandle\b")),
    ("UserDefaults", re.compile(r"\bUserDefaults\b")),
    ("Store.shared.set", re.compile(r"\bStore\.shared\.set\b")),
    ("NSTemporaryDirectory", re.compile(r"\bNSTemporaryDirectory\s*\(")),
    ("applicationSupportDirectory", re.compile(r"\.applicationSupportDirectory\b")),
    ("cachesDirectory", re.compile(r"\.cachesDirectory\b")),
    ("temporaryDirectory", re.compile(r"\.temporaryDirectory\b")),
    ("Reader(...)", re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*Reader\s*\(")),
    ("history: true", re.compile(r"\bhistory\s*:\s*true\b")),
]


@dataclass
class Finding:
    path: Path
    line: int
    type_name: str
    token: str
    source: str


def swift_files() -> list[Path]:
    files: list[Path] = []
    for root in SCAN_ROOTS:
        base = REPO_ROOT / root
        if not base.exists():
            continue
        for path in base.rglob("*.swift"):
            rel = path.relative_to(REPO_ROOT)
            if rel in SKIP_FILES:
                continue
            if any(part in SKIP_PARTS for part in rel.parts):
                continue
            files.append(path)
    return sorted(files)


def find_matching_brace(text: str, open_idx: int) -> int | None:
    depth = 0
    in_string = False
    escaped = False
    in_line_comment = False
    in_block_comment = False
    i = open_idx

    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""

        if in_line_comment:
            if ch == "\n":
                in_line_comment = False
            i += 1
            continue

        if in_block_comment:
            if ch == "*" and nxt == "/":
                in_block_comment = False
                i += 2
            else:
                i += 1
            continue

        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == "\"":
                in_string = False
            i += 1
            continue

        if ch == "/" and nxt == "/":
            in_line_comment = True
            i += 2
            continue
        if ch == "/" and nxt == "*":
            in_block_comment = True
            i += 2
            continue
        if ch == "\"":
            in_string = True
            i += 1
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1

    return None


def declaration_bodies(text: str, pattern: re.Pattern[str]) -> list[tuple[str, int, str]]:
    bodies: list[tuple[str, int, str]] = []
    for match in pattern.finditer(text):
        name = match.group("name")
        if not HISTORY_NAME_RE.search(name):
            continue
        open_idx = text.find("{", match.end())
        if open_idx == -1:
            continue
        close_idx = find_matching_brace(text, open_idx)
        if close_idx is None:
            continue
        start_line = text.count("\n", 0, open_idx) + 1
        bodies.append((name, start_line, text[open_idx:close_idx + 1]))
    return bodies


def history_type_bodies(text: str) -> list[tuple[str, int, str]]:
    return declaration_bodies(text, HISTORY_TYPE_RE) + declaration_bodies(text, HISTORY_EXTENSION_RE)


def line_for_offset(source: str, start_line: int, offset: int) -> int:
    return start_line + source.count("\n", 0, offset)


def scan() -> list[Finding]:
    findings: list[Finding] = []
    for path in swift_files():
        rel = path.relative_to(REPO_ROOT)
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for type_name, start_line, body in history_type_bodies(text):
            for token, pattern in FORBIDDEN_PATTERNS:
                for match in pattern.finditer(body):
                    line = line_for_offset(body, start_line, match.start())
                    source_line = body.splitlines()[line - start_line].strip()
                    findings.append(Finding(rel, line, type_name, token, source_line))
    return findings


def agenthits_db_persistence_guard() -> list[str]:
    path = REPO_ROOT / "Kit/plugins/DB.swift"
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return ["Kit/plugins/DB.swift is missing"]

    required = [
        "persistenceDisabled",
        "shouldDisablePersistence",
        ".AgentHits",
        "guard !self.persistenceDisabled else { return }",
    ]
    return [f"Kit/plugins/DB.swift must keep AgentHits DB persistence disabled: missing `{token}`" for token in required if token not in text]


def write_fixture(root: Path, rel: str, text: str) -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.strip() + "\n", encoding="utf-8")


def run_self_test_case(name: str, files: dict[str, str], should_pass: bool) -> None:
    global REPO_ROOT
    original_root = REPO_ROOT
    with tempfile.TemporaryDirectory(prefix=f"stats-passive-guard-{name}-") as tmp:
        REPO_ROOT = Path(tmp)
        for rel, text in files.items():
            write_fixture(REPO_ROOT, rel, text)
        findings = scan()
        passed = not findings
        if passed != should_pass:
            print(f"Self-test `{name}` failed.")
            print(f"Expected {'pass' if should_pass else 'fail'}, got {'pass' if passed else 'fail'}.")
            for finding in findings:
                print(f"{finding.path}:{finding.line}: {finding.type_name}: {finding.token}")
            REPO_ROOT = original_root
            raise SystemExit(1)
    REPO_ROOT = original_root


def self_test() -> int:
    run_self_test_case(
        "clean-history-store",
        {
            "Modules/Fake/main.swift": """
            final class FakeActivityHistoryStore {
                private var values: [Int] = []

                func record(_ value: Int) {
                    values.append(value)
                    values = Array(values.suffix(24))
                }
            }
            """,
            "Kit/plugins/DB.swift": """
            final class ExistingDB {
                func save() {
                    DB.shared.insert(key: "allowed infrastructure", value: "allowed")
                }
            }
            """,
            "Kit/plugins/Store.swift": """
            final class ExistingStore {
                func save() {
                    Store.shared.set(key: "allowed infrastructure", value: true)
                }
            }
            """,
        },
        should_pass=True,
    )

    forbidden_cases = {
        "db-shared": "DB.shared.insert(key: \"bad\", value: \"bad\")",
        "user-defaults": "UserDefaults.standard.set(true, forKey: \"bad\")",
        "file-manager": "_ = FileManager.default",
        "json-encoder": "_ = JSONEncoder()",
        "json-decoder": "_ = JSONDecoder()",
        "file-write": "try? Data().write(to: URL(fileURLWithPath: \"/tmp/bad\"))",
        "reader-cache": "_ = ProcessReader(.disk)",
        "reader-history": "_ = Reader<Int>(.disk, history: true)",
    }
    for name, line in forbidden_cases.items():
        run_self_test_case(
            name,
            {
                "Modules/Fake/main.swift": f"""
                final class FakeActivityHistoryStore {{
                    func save() {{
                        {line}
                    }}
                }}
                """
            },
            should_pass=False,
        )

    run_self_test_case(
        "extension-db-shared",
        {
            "Modules/Fake/main.swift": """
            final class FakeActivityHistoryStore {
                func record() {}
            }

            extension FakeActivityHistoryStore {
                func save() {
                    DB.shared.insert(key: "bad", value: "bad")
                }
            }
            """
        },
        should_pass=False,
    )

    print("Passive monitoring guard self-tests passed.")
    return 0


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        return self_test()

    findings = scan()
    db_guard_failures = agenthits_db_persistence_guard()
    if findings:
        print("Passive monitoring guard failed.")
        print("Runtime history stores must stay in-memory and bounded by default.")
        print("Do not add DB/JSON/file/UserDefaults persistence or Reader-backed cache to history stores without explicit approval.\n")
        for finding in findings:
            print(f"{finding.path}:{finding.line}: {finding.type_name}: forbidden `{finding.token}`")
            print(f"  {finding.source}")
        return 1
    if db_guard_failures:
        print("Passive monitoring guard failed.")
        print("AgentHits must not persist Reader runtime cache through LevelDB by default.\n")
        for failure in db_guard_failures:
            print(failure)
        return 1

    print("Passive monitoring guard passed: runtime history stores have no forbidden persistence patterns.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
