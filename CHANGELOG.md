# Changelog

## Version 0.1.0

This release represents the major porting effort to modernize the carafe.cr project (a fork of the original criss static site generator) to work with modern Crystal versions and updated dependencies.

### Major Changes

#### Modern Crystal Porting
- **Updated Crystal version requirement**: Now requires Crystal >= 1.18.2
- Applied comprehensive Crystal formatting changes across the codebase
- Fixed all Ameba linting warnings and issues
- Updated codebase to comply with modern Crystal syntax and best practices

#### Sass Implementation Migration
- **Removed old Sass implementation**: Extracted legacy Sass-related code from the core project
- **Added sassd.cr integration**: Now uses [sassd.cr](https://github.com/kritoke/sassd.cr), a modern port of the Dart Sass implementation
- This provides better `sass` compatibility and ongoing maintenance compared to the previous implementation

#### Project Rebranding
- Changed project name from "criss" to "carafe" throughout the source code
- Updated README and documentation to reflect the new project identity

### Code Quality Improvements
- Fixed numerous Ameba linting issues for better code quality
- Applied consistent code formatting using Crystal's formatter
- Improved code organization and maintainability

### Technical Details

#### Dependency Updates
- `sassd.cr`: Added as the new `sass` processing engine
- `crinja`: Updated to master branch from straight-shoota/crinja
- `markd`: Using icyleaf/markd for markdown processing
- `serve`: Using superpaintman/serve for server functionality
- `ameba`: Added as development dependency for linting

#### Refactoring
- Improved permalink handling using a dispatch table pattern
- Cleaned up `sass` integration to be more modular
- Better separation of concerns between core functionality and `sass` processing

### Testing
- All specs now passing after modernization
- Updated tests to work with new Crystal syntax
- Adjusted test expectations to match updated behavior

### Breaking Changes
While this is a major version bump, users should note:
- Requires Crystal >= 1.18.2 (no longer compatible with older versions)
- `sass` processing now uses sassd.cr instead of the previous implementation
- Internal API changes due to refactoring for modern Crystal compatibility

### Migration Guide for Users
If you were using the original criss project:

1. Update your Crystal installation to version 1.18.2 or later
2. Run `shards install` to update dependencies
3. Run `shards build` to rebuild the executable
4. Your existing sites should work without changes, but verify `sass` processing

### Acknowledgments
This project is a fork of the original [criss](https://github.com/straight-shoota/criss) created by Johannes Müller. We thank the original author for the excellent foundation.

### Future Plans
- Continue improving `sass` integration
- Enhance documentation
- Create a new plugin architecture to incoporate popular Jekyll plugins
- Performance optimizations
- Easy to use drop in replacement for generating jekyll sites that is "batteries included."

---

**Note**: This release represents the stabilization of the modern Crystal porting effort. All tests are passing and the project is ready for use, though still in ALPHA status.
