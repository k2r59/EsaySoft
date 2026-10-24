#!/usr/bin/env python3
"""Package local editor-only previews. Never writes /Applications or update feeds."""
from pathlib import Path
import plistlib, shutil, subprocess, sys
product=sys.argv[1]
assert product in ('EasyPaste','EasyShoot')
root=Path(__file__).resolve().parents[1]
cache=Path.home()/'Library/Caches'/('EasyPaste-build' if product=='EasyPaste' else 'EasyShoot-annotation-build')
output=Path.home()/'Desktop/EasySoft - Annotation'
variant=''
app=output/(product+' Atelier'+variant+'.app')
binary=cache/'.build/release'/product
assert binary.is_file(), f'Build {cache} first'
if app.exists():
    # Refuse to touch an unrelated bundle even if its name matches.
    info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    assert info.get('AnnotationPreview') is True
    shutil.rmtree(app)
for part in ('MacOS','Resources','Frameworks'): (app/'Contents'/part).mkdir(parents=True,exist_ok=True)
shutil.copy2(binary,app/'Contents/MacOS'/product)
framework=cache/'.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
subprocess.run(['ditto',str(framework),str(app/'Contents/Frameworks/Sparkle.framework')],check=True)
icon=Path('/Applications')/(product+'.app')/'Contents/Resources'/(product+'.icns')
if icon.exists(): shutil.copy2(icon,app/'Contents/Resources'/icon.name)
shutil.copy2(root/'app'/product/'LICENSE',app/'Contents/Resources/LICENSE.txt')
info=dict(CFBundleName=product+' Atelier'+variant,CFBundleDisplayName=product+' Atelier'+variant,CFBundleExecutable=product,
          CFBundleIdentifier='app.easysoft.annotation-preview.'+product.lower()+'.v2',CFBundlePackageType='APPL',
          CFBundleVersion='1',CFBundleShortVersionString='1.0-test',CFBundleDevelopmentRegion='fr',CFBundleLocalizations=['fr'],
          CFBundleIconFile=product,LSMinimumSystemVersion='15.0',NSHighResolutionCapable=True,LSUIElement=False,
          AnnotationPreview=True,AnnotationPreviewProduct=product)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
# Locally built apps, separate identities, no network entitlements or permission prompts.
subprocess.run(['codesign','--force','--deep','--sign','-',str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print(app)
