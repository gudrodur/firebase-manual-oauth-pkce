# Claude Code Rules for Ekklesia Platform

## CSS Methodology

Our CSS approach is based on two core principles:

### 1. Foundational Global Stylesheet
We establish base styles for typography, colors, spacing, and a CSS reset to ensure project-wide consistency.

- **Purpose**: Establish visual consistency across the entire application
- **Scope**: Global styles (typography, colors, spacing, reset)
- **Location**: Typically in a root/global stylesheet (e.g., `styles/global.css`)

### 2. Bespoke Component Styles
Each component is styled with its own custom, scoped CSS.

- **Purpose**: Keep HTML semantic and maintainable
- **Approach**: Component-specific stylesheets
- **Benefits**:
  - Semantic HTML structure
  - Scoped, maintainable styles
  - No utility-first frameworks (no Tailwind CSS)
  - Clear separation of concerns

### CSS Rules

- ✅ **DO**: Create component-specific stylesheets
- ✅ **DO**: Use semantic HTML with custom CSS classes
- ✅ **DO**: Maintain global consistency through base styles
- ❌ **DON'T**: Use utility-first CSS frameworks (e.g., Tailwind CSS)
- ❌ **DON'T**: Inline styles in HTML (except for dynamic values)
- ❌ **DON'T**: Use generic utility classes throughout HTML

### Example Structure
```
styles/
├── global.css          # Reset, typography, colors, spacing
└── components/
    ├── header.css      # Header-specific styles
    ├── profile.css     # Profile component styles
    └── button.css      # Button component styles
```

## Git Commit Rules

- ❌ NEVER add AI attribution markers to commits
- ✅ All commits are authored by the human user only

## Documentation Rules

- ❌ NEVER include full personal information in public documentation
- ✅ Mask personal information (names, emails, kennitala, etc.)
- See `.code-rules` for complete masking format

## Debugging Approach

- ✅ Always find the root cause before implementing solutions
- ✅ Verify assumptions with actual data (logs, API responses, queries)
- ✅ Work systematically through the data flow
- See `.code-rules` for complete debugging methodology
