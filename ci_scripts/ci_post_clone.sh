#!/bin/sh

# Exit immediately if a command exits with a non-zero status
set -e

# Disable package plugin fingerprint validation (with the Apple intentional typo: Validatation)
defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES

# Also include the correct spelling just in case Apple fixes the typo in the future
defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidation -bool YES

# Skip Macro Fingerprint Validation as well
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
