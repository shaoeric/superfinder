#!/bin/bash
# Shared stable code-signing configuration, sourced by build/setup scripts.

SUPERFINDER_SIGNING_KEYCHAIN="${SUPERFINDER_SIGNING_KEYCHAIN:-$HOME/Library/Keychains/SuperFinder.keychain-db}"
SUPERFINDER_SIGNING_IDENTITY="${SUPERFINDER_SIGNING_IDENTITY:-SuperFinder Local Code Signing}"
SUPERFINDER_SIGNING_PASSWORD_FILE="${SUPERFINDER_SIGNING_PASSWORD_FILE:-$HOME/Library/Keychains/SuperFinder.keychain-password}"
