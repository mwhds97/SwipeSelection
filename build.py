#!/usr/bin/env python3
"""Build the rootful iOS package with a Linux iOS clang/ld toolchain.

The regular Theos Makefile is the preferred build route on macOS. This helper
uses the same Logos source and preference bundle for reproducible local builds.
"""
import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--toolchain', required=True, type=Path, help='toolchain bin directory')
    parser.add_argument('--sdk', required=True, type=Path)
    parser.add_argument('--logos', required=True, type=Path, help='Logos checkout')
    parser.add_argument('--headers', required=True, type=Path, help='Theos headers checkout')
    parser.add_argument('--libraries', required=True, type=Path, help='Theos lib checkout')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    build = root / '.build'
    build.mkdir(exist_ok=True)
    env = os.environ.copy()
    env['PATH'] = str(args.toolchain.resolve()) + os.pathsep + env['PATH']
    env['LD_LIBRARY_PATH'] = str(args.toolchain.resolve().parent / 'lib') + os.pathsep + env.get('LD_LIBRARY_PATH', '')
    log = []

    def run(command, **kwargs):
        command = [str(item) for item in command]
        print('+', ' '.join(command), flush=True)
        result = subprocess.run(command, cwd=root, env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, **kwargs)
        log.append('+ ' + ' '.join(command) + '\n' + result.stdout)
        if result.stdout:
            print(result.stdout, end='', flush=True)
        (build / 'build.log').write_text('\n'.join(log))
        result.check_returncode()
        return result.stdout

    generated = build / 'Tweak.mm'
    logos_output = subprocess.run(['perl', str(args.logos / 'bin/logos.pl'), 'Tweak.xm'],
                                  cwd=root, env=env, text=True, capture_output=True, check=True)
    if logos_output.stderr:
        print(logos_output.stderr)
    generated.write_text(logos_output.stdout)
    products = {'SwipeSelection.dylib': [], 'SwipeSelectionPrefs': []}
    run([args.toolchain / 'clang', '--version'])
    for arch in ['arm64', 'arm64e']:
        archdir = build / arch
        archdir.mkdir(exist_ok=True)
        common = [args.toolchain / 'clang', '-target', arch + '-apple-ios14.0',
                  '-isysroot', args.sdk, '-I', root, '-I', args.headers,
                  '-F', args.libraries, '-fobjc-arc', '-fblocks', '-Os',
                  '-Wall', '-Wextra', '-Wno-unused-parameter', '-Wno-deprecated-declarations',
                  '-fvisibility=hidden']
        objects = []
        for source in [generated, root / 'SSPanGestureRecognizer.m', root / 'SSPreferences.m']:
            obj = archdir / (source.stem + '.o')
            run(common + ['-c', source, '-o', obj])
            objects.append(obj)
        prefs_obj = archdir / 'SSRootListController.o'
        run(common + ['-c', root / 'preferences/SSRootListController.m', '-o', prefs_obj])

        linker = [args.toolchain / 'ld', '-arch', arch, '-dylib',
                  '-ios_version_min', '14.0', '-syslibroot', args.sdk,
                  '-F', args.libraries, '-F', args.sdk / 'System/Library/PrivateFrameworks',
                  '-lSystem', '-lobjc', '-framework', 'UIKit', '-framework', 'Foundation',
                  '-framework', 'CoreFoundation', '-framework', 'CoreGraphics']
        tweak = archdir / 'SwipeSelection.dylib'
        run(linker + ['-lc++', '-framework', 'CydiaSubstrate', '-install_name',
                       '/Library/MobileSubstrate/DynamicLibraries/SwipeSelection.dylib',
                       *objects, '-o', tweak])
        prefs = archdir / 'SwipeSelectionPrefs'
        run(linker + ['-framework', 'Preferences', '-install_name',
                       '/Library/PreferenceBundles/SwipeSelectionPrefs.bundle/SwipeSelectionPrefs',
                       prefs_obj, archdir / 'SSPreferences.o', '-o', prefs])
        products['SwipeSelection.dylib'].append(tweak)
        products['SwipeSelectionPrefs'].append(prefs)

    stage = build / 'stage'
    if stage.exists():
        shutil.rmtree(stage)
    shutil.copytree(root / 'layout', stage)
    tweakdir = stage / 'Library/MobileSubstrate/DynamicLibraries'
    prefsdir = stage / 'Library/PreferenceBundles/SwipeSelectionPrefs.bundle'
    tweakdir.mkdir(parents=True)
    shutil.copytree(root / 'preferences/Resources', prefsdir)
    for scale in ['2x', '3x']:
        shutil.copy2(root / ('Icon@' + scale + '.png'), prefsdir)
    # Binary property lists match Theos release packaging.
    for path in stage.rglob('*.plist'):
        with path.open('rb') as stream:
            value = plistlib.load(stream)
        path.write_bytes(plistlib.dumps(value, fmt=plistlib.FMT_BINARY))
    filter_value = {'Filter': {'Bundles': ['com.apple.UIKit']}}
    (tweakdir / 'SwipeSelection.plist').write_bytes(plistlib.dumps(filter_value, fmt=plistlib.FMT_BINARY))
    for name, slices in products.items():
        output = (tweakdir if name.endswith('.dylib') else prefsdir) / name
        run([args.toolchain / 'lipo', '-create', *slices, '-output', output])
        run([args.toolchain / 'ldid', '-S', output])
        output.chmod(0o755)
        run([args.toolchain / 'lipo', '-info', output])
    control_dir = stage / 'DEBIAN'
    control_dir.mkdir()
    control_text = (root / 'control').read_text().rstrip() + '\n'
    installed = sum(p.stat().st_size for p in stage.rglob('*') if p.is_file())
    (control_dir / 'control').write_text(control_text + 'Installed-Size: ' + str((installed + 1023) // 1024) + '\n')
    (control_dir / 'control').chmod(0o644)
    package_dir = root / 'packages'
    package_dir.mkdir(exist_ok=True)
    metadata = dict(line.split(': ', 1) for line in control_text.splitlines() if ': ' in line)
    package = package_dir / ('{Package}_{Version}_{Architecture}.deb'.format(**metadata))
    run(['dpkg-deb', '--root-owner-group', '-Zxz', '--build', stage, package])
    print('SHA256', hashlib.sha256(package.read_bytes()).hexdigest())
    print(package)


if __name__ == '__main__':
    main()
