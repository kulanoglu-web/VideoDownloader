# VideoDownloader – Projektstart

Werbefreier Flutter-Prototyp für Android und Windows. **Keine fertige TubeMate-Alternative.**

## Ist-Stand
- Download direkter HTTP(S)-Links auf MP4, M4A, MP3, WebM und MOV.
- Fortschritt, Abbruch, lokale Speicherung im App-Dokumentenordner.
- Kein YouTube-Extractor, keine Mehrquellen-Erkennung, kein MP3-Konverter, keine Hintergrunddownloads.
- Keine DRM-Umgehung.

## GitHub Actions
Unter Actions > Build Android and Windows den Workflow starten. Bei Push auf main startet der Build automatisch. Unter dem Workflow-Run stehen Artefakte, falls der Build erfolgreich ist.

## Hinweise
Android-App-Dateien liegen zunächst im App-Dokumentenordner. Windows-Build enthält eine portable EXE mit Begleitdateien, noch keinen Installer. Plattformdateien werden im CI durch flutter create generiert. Builds sind nicht verifiziert.
