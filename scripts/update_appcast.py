#!/usr/bin/env python3
"""Insert (or replace) a Sparkle appcast item for a release.

Inputs come from environment variables — populated by .github/workflows/release.yml:
  REPO        owner/repo   e.g. xiangst0816/scribe
  TAG         git tag      e.g. v0.2.0
  VERSION    sanitized version string used in the .app's CFBundleShortVersionString
  ED_SIG      EdDSA signature from `sign_update`
  LENGTH      file size in bytes
  PUB_DATE    RFC-822 date string

The appcast lives at web/public/appcast.xml and is served by GitHub Pages.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

PATH = Path("web/public/appcast.xml")


def env(name: str) -> str:
    val = os.environ.get(name, "").strip()
    if not val:
        sys.exit(f"missing required env var: {name}")
    return val


def main() -> None:
    repo = env("REPO")
    tag = env("TAG")
    version = env("VERSION")
    ed_sig = env("ED_SIG")
    length = env("LENGTH")
    pub_date = env("PUB_DATE")

    download_url = f"https://github.com/{repo}/releases/download/{tag}/Scribe.zip"
    notes_url = f"https://github.com/{repo}/releases/tag/{tag}"

    item = (
        "    <item>\n"
        f"      <title>Version {version}</title>\n"
        f"      <link>{notes_url}</link>\n"
        f"      <sparkle:version>{version}</sparkle:version>\n"
        f"      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>\n"
        "      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>\n"
        f"      <pubDate>{pub_date}</pubDate>\n"
        f'      <enclosure url="{download_url}"\n'
        f'                 sparkle:edSignature="{ed_sig}"\n'
        f'                 length="{length}"\n'
        '                 type="application/octet-stream"/>\n'
        "    </item>\n"
    )

    if PATH.exists():
        xml = PATH.read_text()
        # Remove a previous entry for the same version so re-runs are idempotent.
        existing = re.compile(
            r"    <item>\s*<title>Version "
            + re.escape(version)
            + r"</title>.*?</item>\s*",
            re.DOTALL,
        )
        if existing.search(xml):
            xml = existing.sub("", xml, count=1)
            print(f"Replaced existing entry for {version}.")
        # Insert new item right after <channel> (and any leading metadata block).
        inserted = re.sub(
            r"(<channel>\s*"
            r"(?:<title>[^<]*</title>\s*)?"
            r"(?:<link>[^<]*</link>\s*)?"
            r"(?:<description>[^<]*</description>\s*)?"
            r"(?:<language>[^<]*</language>\s*)?)",
            lambda m: m.group(1) + item,
            xml,
            count=1,
        )
        PATH.write_text(inserted)
    else:
        PATH.parent.mkdir(parents=True, exist_ok=True)
        feed_url = f"https://{repo.split('/')[0]}.github.io/scribe/appcast.xml"
        PATH.write_text(
            '<?xml version="1.0" standalone="yes"?>\n'
            '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"\n'
            '     xmlns:dc="http://purl.org/dc/elements/1.1/"\n'
            '     version="2.0">\n'
            "  <channel>\n"
            "    <title>Scribe</title>\n"
            f"    <link>{feed_url}</link>\n"
            "    <description>Scribe — local dictation for macOS.</description>\n"
            "    <language>en</language>\n"
            f"{item}"
            "  </channel>\n"
            "</rss>\n"
        )

    print(f"Wrote {PATH}")


if __name__ == "__main__":
    main()
