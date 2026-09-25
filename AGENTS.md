# SIESAS Development Instructions

## Project

SIESAS is a graduation/capstone project developed in Flutter.

Current development scope is the Executive Module.

Do not implement Citizen functionality unless explicitly requested.

## Current functional scope

Main Executive features include:

- Password recovery
- Registering requests from the Executive module
- Dashboard indicators
- Drill-down from indicators
- Filtering and querying database information

## Data

The application uses MySQL.

Use database-backed information for analytics.

Do not introduce time/SLA-based metrics unless explicitly requested.

## UI

Follow the existing SIESAS wireframes and design system.

Do not redesign screens unnecessarily.

Prefer reusable Flutter widgets.

The application is primarily a web interface.

## Development rules

Before modifying code:

1. Inspect the existing implementation.
2. Understand the affected architecture.
3. Identify the files that need modification.
4. Avoid unnecessary refactors.

After modifying code:

1. Format the code.
2. Run `flutter analyze`.
3. Run relevant tests.
4. Verify the affected screen/functionality.
5. Report what changed.

## Skills

Use the relevant repository skill when the task matches it.

- `$siesas-architecture` for architectural or functional decisions.
- `$flutter-ui` for Flutter screens and UI changes.
- `$database` for MySQL/database work.
- `$testing` when creating or modifying tests.
- `$code-verification` after substantial code changes.