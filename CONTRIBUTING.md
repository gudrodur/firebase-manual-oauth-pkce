# Contributing to Firebase Manual OAuth with PKCE

Thank you for considering contributing to this project!

## Code of Conduct

Be respectful, inclusive, and constructive.

## How to Contribute

### Reporting Bugs

1. Check if the bug is already reported in [Issues](../../issues)
2. Create a new issue with:
   - Clear title and description
   - Steps to reproduce
   - Expected vs actual behavior
   - Environment (OS, Node.js version, Firebase SDK version)
   - Cloud Function logs (redact secrets!)
   - Browser console output (if frontend issue)

### Suggesting Features

1. Check existing issues for similar suggestions
2. Create an issue describing:
   - Use case and motivation
   - Proposed solution
   - Alternative approaches considered

### Pull Requests

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/my-feature`
3. **Make your changes**:
   - Follow existing code style
   - Add tests if applicable
   - Update documentation
4. **Test your changes**:
   - Deploy Cloud Function to test project
   - Test with real OAuth provider
   - Verify all examples work
5. **Commit with clear message**: `git commit -m "feat: add X feature"`
6. **Push to your fork**: `git push origin feature/my-feature`
7. **Open a Pull Request**

### Commit Message Format

Follow [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation changes
- `style:` - Code style changes (formatting, etc.)
- `refactor:` - Code refactoring
- `test:` - Adding or updating tests
- `chore:` - Maintenance tasks

Examples:
```
feat: add support for Auth0 provider
fix: handle expired tokens correctly
docs: update integration guide with ngrok instructions
```

## Development Setup

### Prerequisites

- Node.js 18+
- Python 3.9+
- Firebase CLI
- Google Cloud SDK
- Git

### Local Development

1. **Clone repository**:
   ```bash
   git clone https://github.com/your-org/firebase-manual-oauth-pkce.git
   cd firebase-manual-oauth-pkce
   ```

2. **Install dependencies**:
   ```bash
   cd functions
   pip install -r requirements.txt
   ```

3. **Configure test project**:
   ```bash
   cp .firebaserc.example .firebaserc
   # Edit .firebaserc with your test project
   ```

4. **Set up environment**:
   ```bash
   cd functions
   cp .env.example .env
   # Edit .env with test credentials
   ```

5. **Run tests** (if available):
   ```bash
   pytest
   ```

### Testing

**Cloud Function**:
```bash
# Deploy to test project
firebase deploy --only functions:handleOAuthCallback --project=test-project

# Test with curl
curl -X POST https://your-function-url \
  -H "Content-Type: application/json" \
  -d '{"code":"test-code","codeVerifier":"test-verifier"}'
```

**Frontend**:
```bash
# Serve locally
cd frontend/examples/vanilla
npx http-server -p 8080

# Test in browser
open http://localhost:8080
```

**Integration Test**:
```bash
# Deploy to Firebase Hosting preview
firebase hosting:channel:deploy test

# Test full OAuth flow
```

## Code Style

### Python

Follow [PEP 8](https://pep8.org/):
- 4 spaces for indentation
- Max line length: 100 characters
- Use type hints where possible
- Docstrings for functions

```python
def exchange_tokens(code: str, verifier: str) -> Dict[str, Any]:
    """
    Exchange authorization code for tokens.

    Args:
        code: Authorization code from OAuth provider
        verifier: PKCE code verifier

    Returns:
        Token response with id_token and access_token

    Raises:
        requests.HTTPError: If token exchange fails
    """
    # Implementation
```

### JavaScript

Follow [Airbnb Style Guide](https://github.com/airbnb/javascript):
- 2 spaces for indentation
- Use ES6+ features
- Async/await over Promises
- JSDoc comments for functions

```javascript
/**
 * Generate PKCE parameters
 * @returns {Promise<{verifier: string, challenge: string}>}
 */
async function generatePKCE() {
  // Implementation
}
```

### Documentation

- Use Markdown for all docs
- Include code examples
- Add screenshots where helpful
- Keep line length < 100 characters

## Security

### Reporting Security Issues

**DO NOT** open public issues for security vulnerabilities.

Instead, email security details to: [security contact email]

Include:
- Description of vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We will respond within 48 hours.

### Security Guidelines

- Never commit secrets (use Secret Manager)
- Always validate user inputs
- Use parameterized queries
- Follow principle of least privilege
- Keep dependencies updated

## Documentation

When adding features, update:
- README.md (if user-facing)
- docs/INTEGRATION.md (if setup changes)
- docs/ARCHITECTURE.md (if design changes)
- Code comments (always!)

## Release Process

Maintainers will:
1. Review and merge PRs
2. Update CHANGELOG.md
3. Create git tag (e.g., `v1.2.0`)
4. Create GitHub release
5. Update documentation

## Questions?

- Check [docs/](docs/) directory
- Search existing [Issues](../../issues)
- Start a [Discussion](../../discussions)

Thank you for contributing! 🎉
