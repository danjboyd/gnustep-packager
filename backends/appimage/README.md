# AppImage Backend

## Purpose
The AppImage backend will package a staged GNUstep application into a Linux
AppImage.

## Planned Target
- clang-based GNUstep builds on Linux
- AppDir transform plus AppImage artifact generation

## Shared Inputs
- package manifest
- staged payload
- launch contract

## Backend Responsibilities
- transform the staged payload into an AppDir
- generate `AppRun`
- render desktop metadata and icons
- emit AppImage artifacts and validation logs

## Design Constraint
This backend should extend the shared package model rather than force a redesign
of the core contract built for MSI.

## Current Phase 2 State
The backend currently exposes a package-dispatch stub for shared CLI testing.
Real AppDir and AppImage work starts in later phases.
