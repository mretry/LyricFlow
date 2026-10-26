#!/usr/bin/env python3
"""Apply iOS plist capabilities after `flutter create` generates Runner/Info.plist."""
from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print('Usage: python scripts/configure_ios_files.py ios/Runner/Info.plist', file=sys.stderr)
        return 2
    plist_path = Path(sys.argv[1])
    if not plist_path.is_file():
        print(f'Info.plist not found: {plist_path}', file=sys.stderr)
        return 1

    with plist_path.open('rb') as stream:
        data = plistlib.load(stream)

    # Makes the app's Documents directory visible under Files > On My iPhone/iPad.
    data['CFBundleDisplayName'] = 'LyricFlow'
    data['UIFileSharingEnabled'] = True
    data['LSSupportsOpeningDocumentsInPlace'] = True
    data['NSCameraUsageDescription'] = (
        '用于扫描电脑端 LyricFlow 局域网共享二维码，以导入媒体和字幕文件。'
    )
    data['NSLocalNetworkUsageDescription'] = (
        '用于连接同一 Wi-Fi 下的电脑并导入用户选择的媒体和字幕文件。'
    )

    # The companion PC tool serves only on the local network over HTTP.
    ats = data.setdefault('NSAppTransportSecurity', {})
    ats['NSAllowsLocalNetworking'] = True

    with plist_path.open('wb') as stream:
        plistlib.dump(data, stream, sort_keys=False)

    # Flutter 3.47 uses iOS 15+. Never lower a project's existing target.
    project_file = plist_path.parent.parent / 'Runner.xcodeproj' / 'project.pbxproj'
    if project_file.is_file():
        project_text = project_file.read_text(encoding='utf-8')
        project_text = re.sub(
            r'IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);',
            lambda match: (
                'IPHONEOS_DEPLOYMENT_TARGET = 15.0;'
                if tuple(map(int, match.group(1).split('.'))) < (15, 0)
                else match.group(0)
            ),
            project_text,
        )
        project_file.write_text(project_text, encoding='utf-8')
        print(f'Ensured iOS deployment target is at least 15.0: {project_file}')

    print(f'Configured iOS Files, camera, local-network and ATS settings: {plist_path}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
