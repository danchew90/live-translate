# CLAUDE.md - AI Assistant Guide for live-translate

This document provides guidance for AI assistants (like Claude) working with the live-translate codebase.

## Project Overview

**Repository:** live-translate
**Status:** New project (initial setup)
**Purpose:** Live translation application (real-time language translation service)

> **Note:** This is a newly initialized repository. This document will be updated as the codebase develops.

---

## Quick Start

```bash
# Clone the repository
git clone <repository-url>
cd live-translate

# Install dependencies (once package.json is created)
npm install

# Start development server (once configured)
npm run dev
```

---

## Project Structure

```
live-translate/
├── CLAUDE.md           # This file - AI assistant guidance
├── README.md           # Project documentation (to be created)
├── package.json        # Dependencies and scripts (to be created)
├── src/                # Source code (to be created)
│   ├── index.ts        # Application entry point
│   ├── components/     # UI components
│   ├── services/       # Business logic and API services
│   ├── utils/          # Utility functions
│   └── types/          # TypeScript type definitions
├── tests/              # Test files
├── config/             # Configuration files
└── docs/               # Additional documentation
```

---

## Development Guidelines

### Code Style

- Use TypeScript for type safety
- Follow consistent naming conventions:
  - `camelCase` for variables and functions
  - `PascalCase` for classes and components
  - `UPPER_SNAKE_CASE` for constants
- Keep functions small and focused (single responsibility)
- Write self-documenting code; add comments only for complex logic

### Git Workflow

- Create feature branches from main: `feature/<description>`
- Use descriptive commit messages in imperative mood
- Keep commits atomic and focused
- Run tests before committing

### Testing

- Write tests alongside new features
- Maintain test coverage for critical paths
- Use descriptive test names that explain the expected behavior

---

## Common Tasks

### Adding a New Feature

1. Create a feature branch
2. Implement the feature with tests
3. Update documentation if needed
4. Submit for review

### Fixing a Bug

1. Reproduce the issue
2. Write a failing test that exposes the bug
3. Fix the bug
4. Verify the test passes

### Running Tests

```bash
# Run all tests (once configured)
npm test

# Run tests in watch mode
npm run test:watch

# Run with coverage
npm run test:coverage
```

---

## Architecture Notes

### Key Technologies (Planned)

- **Language:** TypeScript
- **Runtime:** Node.js
- **Translation APIs:** To be determined (Google Translate, DeepL, etc.)
- **Real-time Communication:** WebSockets or Server-Sent Events

### Design Principles

1. **Modularity:** Keep components loosely coupled
2. **Extensibility:** Design for easy addition of new translation providers
3. **Performance:** Optimize for low-latency real-time translation
4. **Error Handling:** Graceful degradation when services are unavailable

---

## Important Files

| File | Purpose |
|------|---------|
| `CLAUDE.md` | AI assistant guidance (this file) |
| `package.json` | Dependencies and npm scripts |
| `tsconfig.json` | TypeScript configuration |
| `.env` | Environment variables (not committed) |
| `.env.example` | Template for environment variables |

---

## Environment Variables

Create a `.env` file based on `.env.example`:

```bash
# API Keys (do not commit actual values)
TRANSLATION_API_KEY=your_api_key_here

# Server Configuration
PORT=3000
NODE_ENV=development

# Logging
LOG_LEVEL=debug
```

---

## AI Assistant Guidelines

When working with this codebase, AI assistants should:

### Do

- Read existing code before making modifications
- Follow established patterns and conventions in the codebase
- Write tests for new functionality
- Keep changes focused and minimal
- Use TypeScript types properly
- Handle errors appropriately
- Update this CLAUDE.md when significant architectural changes are made

### Don't

- Make changes without understanding the context
- Over-engineer solutions
- Add unnecessary dependencies
- Skip error handling
- Commit sensitive data (API keys, credentials)
- Make breaking changes without clear communication

### Code Review Checklist

Before completing a task, verify:

- [ ] Code follows project conventions
- [ ] Tests pass
- [ ] No security vulnerabilities introduced
- [ ] No sensitive data exposed
- [ ] Changes are minimal and focused
- [ ] Documentation updated if needed

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| Dependencies not installing | Delete `node_modules` and `package-lock.json`, then run `npm install` |
| TypeScript errors | Check `tsconfig.json` and ensure types are installed |
| Tests failing | Check for environment variables and mock configurations |

---

## Resources

- [TypeScript Documentation](https://www.typescriptlang.org/docs/)
- [Node.js Documentation](https://nodejs.org/docs/)
- [Project Issue Tracker](https://github.com/danchew90/live-translate/issues)

---

## Changelog

### Initial Setup (2026-02-03)
- Created CLAUDE.md with foundational project guidelines
- Established code style and development workflow conventions
- Defined project structure template

---

*This document is maintained for AI assistants working with this codebase. Update it when making significant changes to the project structure, conventions, or workflows.*
