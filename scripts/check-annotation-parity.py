#!/usr/bin/env python3
"""Keep the vendored editor identical in both standalone source archives."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
files=['AnnotationBackdrop','AnnotationModel','AnnotationCanvas','AnnotationView','AnnotationActions','AnnotationPreview','ChromeGlass']
for name in files:
    paste=root/'app/EasyPaste/Sources/EasyPaste'/(name+'.swift')
    shoot=root/'app/EasyShoot/Sources/EasyShoot'/(name+'.swift')
    assert paste.read_bytes()==shoot.read_bytes(), f'Editor differs: {name}'
print(f'{len(files)} shared editor files match in EasyPaste and EasyShoot.')
