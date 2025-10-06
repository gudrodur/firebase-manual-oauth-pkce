# Firebase Manual OAuth with PKCE

**Production-ready Firebase authentication for OAuth providers requiring PKCE**

## The Problem

Firebase Identity Platform's OIDC provider cannot support OAuth flows that require PKCE (Proof Key for Code Exchange):

- Firebase JS SDK can send `code_challenge` during authorization
- But Firebase's backend handles token exchange and **cannot send `code_verifier`**
- The verifier is stored in client-side `sessionStorage` - Firebase's backend has no access to it
- Many OAuth providers (like Iceland's Kenni.is eID) **require** PKCE for security

**Result**: Firebase's built-in OIDC provider fails with providers requiring PKCE.

Related: [firebase/firebase-js-sdk#5935](https://github.com/firebase/firebase-js-sdk/issues/5935)

## The Solution

This repository implements a **Manual OAuth Flow** that bypasses Firebase's OIDC provider entirely:

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐     ┌──────────────┐
│   Frontend  │────▶│ OAuth Provider│────▶│ Cloud Function  │────▶│   Firebase   │
│             │     │  (with PKCE)  │     │                 │     │     Auth     │
└─────────────┘     └──────────────┘     └─────────────────┘     └──────────────┘
      │                     │                       │                     │
      │  1. Generate PKCE   │                       │                     │
      │  2. Redirect ───────▶                       │                     │
      │                     │  3. Return auth code  │                     │
      │  ◀─────────────────────────────────────────│                     │
      │  4. Send code + verifier ──────────────────▶                     │
      │                     │  5. Exchange for tokens                     │
      │                     │  ◀──────────────────▶                       │
      │                     │  6. Verify JWT        │                     │
      │                     │  7. Create custom token ───────────────────▶
      │  8. Sign in with custom token ─────────────────────────────────▶ │
      │                     │                       │                     │
      └─────────────────────┴───────────────────────┴─────────────────────┘
```

### Why This Works

1. **Frontend generates PKCE** - Creates `code_verifier` and `code_challenge` in browser
2. **OAuth provider authenticates** - User logs in with PKCE-protected flow
3. **Frontend receives authorization code** - Provider redirects back with code
4. **Frontend sends code + verifier to Cloud Function** - Both pieces available!
5. **Cloud Function exchanges for tokens** - Has access to both code and verifier
6. **Cloud Function verifies JWT** - Validates token from OAuth provider
7. **Cloud Function creates Firebase custom token** - Generates authenticated token
8. **Frontend signs in with custom token** - User is now authenticated in Firebase

## Features

- ✅ **Full PKCE Support** - Works with OAuth providers requiring PKCE
- ✅ **Secure Token Exchange** - Server-side verification and custom token generation
- ✅ **User Profile Management** - Automatic Firestore profile creation
- ✅ **Custom Claims** - Support for provider-specific claims (e.g., national ID)
- ✅ **Production Ready** - Deployed and tested in production environment
- ✅ **Framework Agnostic** - Works with React, Vue, Vanilla JS, or any frontend

## Quick Start

### 1. Deploy Cloud Function

```bash
cd functions
firebase deploy --only functions:handleOAuthCallback
```

### 2. Configure OAuth Provider

Add your Cloud Function URL as redirect URI:
```
https://your-region-your-project.cloudfunctions.net/handleOAuthCallback
```

### 3. Add to Your Frontend

```javascript
import { signInWithOAuth } from './auth/oauth-handler.js';

// Initiate OAuth flow
await signInWithOAuth({
  providerId: 'your-provider',
  clientId: 'your-client-id',
  redirectUri: 'https://your-app.com/callback'
});
```

See [docs/INTEGRATION.md](docs/INTEGRATION.md) for complete setup instructions.

## Documentation

- [Integration Guide](docs/INTEGRATION.md) - Complete setup and deployment
- [Architecture](docs/ARCHITECTURE.md) - How it works under the hood
- [Configuration](docs/CONFIGURATION.md) - Environment variables and settings
- [Security](docs/SECURITY.md) - Security considerations and best practices
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues and solutions

## Examples

Framework-specific examples are available in [`frontend/examples/`](frontend/examples/):

- [Vanilla JavaScript](frontend/examples/vanilla/) - Pure JS implementation
- [React](frontend/examples/react/) - React hooks and components
- [Vue](frontend/examples/vue/) - Vue 3 Composition API

## Requirements

- Firebase project with Identity Platform enabled
- Google Cloud project with Cloud Functions enabled
- OAuth provider configured with PKCE support
- Node.js 18+ (for Cloud Functions)

## License

MIT

## Credits

Developed for integrating Iceland's Kenni.is eID with Firebase Identity Platform.

This pattern solves a fundamental limitation in Firebase's OIDC provider and can be used with any OAuth provider requiring PKCE.
