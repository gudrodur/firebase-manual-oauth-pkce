# Architecture Overview

This document explains how Firebase Manual OAuth with PKCE works under the hood.

## The PKCE Problem with Firebase

### What is PKCE?

PKCE (Proof Key for Code Exchange, RFC 7636) is a security extension for OAuth 2.0:

1. Client generates random `code_verifier`
2. Client creates `code_challenge` = BASE64URL(SHA256(code_verifier))
3. Client sends `code_challenge` to authorization server
4. Authorization server stores `code_challenge`
5. Authorization server returns `authorization_code`
6. Client sends `authorization_code` + `code_verifier` to token endpoint
7. Token endpoint verifies: SHA256(code_verifier) == stored code_challenge
8. If valid, token endpoint returns tokens

**Key Point**: The same client that initiated the flow MUST complete the token exchange.

### Why Firebase Can't Do PKCE

Firebase Identity Platform's OIDC provider has a critical limitation:

```
┌─────────────┐
│   Browser   │  1. Generate code_verifier (stored in sessionStorage)
│             │  2. Send code_challenge to Firebase
└─────┬───────┘
      │
      ▼
┌─────────────┐
│  Firebase   │  3. Firebase redirects to OAuth provider
│  JS SDK     │     (with code_challenge)
└─────┬───────┘
      │
      ▼
┌─────────────┐
│   OAuth     │  4. User authenticates
│  Provider   │  5. Returns authorization_code to Firebase
└─────┬───────┘
      │
      ▼
┌─────────────┐
│  Firebase   │  6. ❌ PROBLEM: Firebase backend needs code_verifier
│  Backend    │     but it's in browser's sessionStorage!
│             │     Firebase backend can't access it!
└─────────────┘
```

**The Problem**: Firebase's backend handles the token exchange, but the `code_verifier` is stored in the client's `sessionStorage`. There's no way for Firebase's backend to access it.

**Result**: Token exchange fails because Firebase can't send the `code_verifier`.

## Our Solution: Manual OAuth Flow

We bypass Firebase's OIDC provider entirely and implement the OAuth flow manually:

```
┌──────────────────────────────────────────────────────────────────────┐
│                         Frontend (Browser)                            │
│                                                                        │
│  1. Generate PKCE                                                      │
│     code_verifier = random(32 bytes)                                  │
│     code_challenge = BASE64URL(SHA256(code_verifier))                 │
│     Store code_verifier in sessionStorage                             │
│                                                                        │
│  2. Redirect to OAuth provider                                        │
│     https://idp.provider.com/auth?                                    │
│       client_id=...&                                                  │
│       redirect_uri=https://my-function.cloudfunctions.net/callback&  │
│       code_challenge=...&                                             │
│       code_challenge_method=S256                                      │
└────────────────────────────┬───────────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────────┐
│                      OAuth Provider                                   │
│                                                                        │
│  3. User authenticates                                                │
│  4. Store code_challenge                                              │
│  5. Redirect back with authorization_code                             │
│     https://my-function.cloudfunctions.net/callback?code=...          │
└────────────────────────────┬───────────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────────┐
│                  Frontend (Browser) - Callback Page                   │
│                                                                        │
│  6. Extract authorization_code from URL                               │
│  7. Retrieve code_verifier from sessionStorage                        │
│  8. Send both to Cloud Function:                                      │
│     POST https://my-function.cloudfunctions.net/callback              │
│     { code: "...", codeVerifier: "..." }                             │
└────────────────────────────┬───────────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    Cloud Function (Python)                            │
│                                                                        │
│  9. Exchange code for tokens (with PKCE verifier!)                    │
│     POST https://idp.provider.com/token                               │
│     {                                                                 │
│       grant_type: "authorization_code",                               │
│       code: "...",                                                    │
│       code_verifier: "...",  ← Has access to verifier!               │
│       client_id: "...",                                               │
│       client_secret: "..."                                            │
│     }                                                                 │
│                                                                        │
│ 10. Receive tokens from OAuth provider                                │
│     { id_token: "...", access_token: "..." }                         │
│                                                                        │
│ 11. Verify ID token (JWT)                                             │
│     - Fetch JWKS from provider                                        │
│     - Verify signature                                                │
│     - Verify audience, issuer, expiration                             │
│                                                                        │
│ 12. Extract claims from ID token                                      │
│     { sub: "...", email: "...", national_id: "..." }                 │
│                                                                        │
│ 13. Create/update user profile in Firestore                           │
│     users/{uid}: {                                                    │
│       email: "...",                                                   │
│       name: "...",                                                    │
│       national_id: "...",                                             │
│       updated_at: timestamp                                           │
│     }                                                                 │
│                                                                        │
│ 14. Create Firebase custom token                                      │
│     firebase_admin.auth.create_custom_token(                          │
│       uid,                                                            │
│       developer_claims={'national_id': '...'}                         │
│     )                                                                 │
│                                                                        │
│ 15. Return custom token to frontend                                   │
│     { customToken: "...", uid: "..." }                               │
└────────────────────────────┬───────────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────────┐
│                  Frontend (Browser) - Callback Page                   │
│                                                                        │
│ 16. Sign in to Firebase with custom token                             │
│     signInWithCustomToken(auth, customToken)                          │
│                                                                        │
│ 17. User is now authenticated in Firebase!                            │
│     - Has Firebase ID token                                           │
│     - Can access Firestore with security rules                        │
│     - Custom claims available (national_id, etc.)                     │
└──────────────────────────────────────────────────────────────────────┘
```

## Key Components

### 1. Frontend OAuth Handler

**File**: `frontend/auth/oauth-handler.js`

**Responsibilities**:
- Generate PKCE parameters using Web Crypto API
- Build authorization URL with OAuth provider
- Store `code_verifier` in sessionStorage
- Handle OAuth callback
- Send code + verifier to Cloud Function
- Sign in to Firebase with custom token

**Security**:
- Uses cryptographically secure random number generation
- Stores verifier in sessionStorage (cleared after use)
- Validates state parameter (CSRF protection)
- Cleans up sensitive data after authentication

### 2. Cloud Function

**File**: `functions/main.py`

**Responsibilities**:
- Receive authorization code and PKCE verifier
- Exchange code for tokens (using PKCE verifier)
- Verify JWT from OAuth provider
- Create/update user profile in Firestore
- Generate Firebase custom token
- Return custom token to frontend

**Security**:
- Client secret stored in Secret Manager (not in code)
- JWT verification using provider's JWKS
- Validates audience, issuer, expiration
- CORS configured for specific origins
- Structured error handling (no secret leakage)

### 3. Firestore User Profiles

**Collection**: `users/{uid}`

**Document Structure**:
```javascript
{
  sub: "oauth-provider-subject-id",
  email: "user@example.com",
  name: "Full Name",
  given_name: "First",
  family_name: "Last",
  phone_number: "+1234567890",  // Phone number (if provided by OAuth)
  national_id: "123456-7890",  // Custom claim (optional)
  updated_at: Timestamp
}
```

**Purpose**:
- Store user profile data from OAuth provider
- Enable profile lookups without re-authenticating
- Support custom claims not in standard OpenID Connect

## Security Considerations

### PKCE Protection

PKCE protects against authorization code interception:

1. Attacker intercepts `authorization_code`
2. Attacker tries to exchange code for tokens
3. Token endpoint requires `code_verifier`
4. Attacker doesn't have `code_verifier` (only victim's browser has it)
5. Token exchange fails ❌

**Why it matters**: Without PKCE, mobile apps and SPAs are vulnerable to code interception attacks.

### State Parameter

The `state` parameter protects against CSRF attacks:

1. Client generates random `state` value
2. Client stores `state` in sessionStorage
3. OAuth provider returns `state` in callback
4. Client verifies: received state == stored state
5. If mismatch, reject the callback

**Why it matters**: Prevents attackers from tricking users into authenticating with attacker's account.

### Custom Token Security

Firebase custom tokens are secure because:

1. Only server with Firebase Admin SDK can create them
2. Signed with Firebase service account private key
3. Short-lived (1 hour expiration)
4. Can include custom claims for authorization
5. Validated by Firebase on sign-in

**Why it matters**: Attackers can't forge custom tokens without the private key.

### JWT Verification

The Cloud Function verifies OAuth provider's ID token:

1. Fetch JWKS (JSON Web Key Set) from provider
2. Extract signing key using token's `kid` (key ID)
3. Verify signature using RS256 algorithm
4. Validate `aud` (audience) matches client ID
5. Validate `iss` (issuer) matches provider URL
6. Validate `exp` (expiration) is in future

**Why it matters**: Prevents token forgery and replay attacks.

## Data Flow Diagram

```
┌─────────────┐
│   Browser   │ code_verifier stored here (sessionStorage)
└──────┬──────┘
       │
       │ 1. Redirect with code_challenge
       ▼
┌─────────────┐
│   OAuth     │ code_challenge stored here
│  Provider   │
└──────┬──────┘
       │
       │ 2. Return authorization_code
       ▼
┌─────────────┐
│   Browser   │ Has both code and code_verifier!
└──────┬──────┘
       │
       │ 3. Send code + code_verifier
       ▼
┌─────────────┐
│   Cloud     │ Can complete token exchange!
│  Function   │
└──────┬──────┘
       │
       │ 4. Exchange code + verifier for tokens
       ▼
┌─────────────┐
│   OAuth     │ Verifies: SHA256(code_verifier) == code_challenge ✓
│  Provider   │ Returns: id_token, access_token
└──────┬──────┘
       │
       │ 5. Return tokens
       ▼
┌─────────────┐
│   Cloud     │ Verify ID token, create custom token
│  Function   │
└──────┬──────┘
       │
       │ 6. Return custom_token
       ▼
┌─────────────┐
│   Browser   │ Sign in to Firebase with custom_token
└──────┬──────┘
       │
       │ 7. Verify custom_token
       ▼
┌─────────────┐
│  Firebase   │ User authenticated! ✓
│    Auth     │
└─────────────┘
```

## Comparison: Firebase OIDC vs Manual OAuth

| Feature | Firebase OIDC Provider | Manual OAuth (This Repo) |
|---------|----------------------|--------------------------|
| **PKCE Support** | ❌ No (backend can't access verifier) | ✅ Yes (full support) |
| **Setup Complexity** | ⭐ Low (few clicks in console) | ⭐⭐⭐ Medium (deploy function, configure) |
| **Custom Claims** | ⚠️ Limited (standard OpenID claims) | ✅ Full (any claim from ID token) |
| **User Profiles** | ❌ No (only in Auth) | ✅ Yes (Firestore) |
| **Token Refresh** | ✅ Automatic | ⚠️ Manual (implement if needed) |
| **Security** | ✅ Good (no PKCE) | ✅ Excellent (with PKCE) |
| **Flexibility** | ⚠️ Limited | ✅ High (full control) |

## When to Use This Solution

✅ **Use Manual OAuth when**:
- OAuth provider requires PKCE (e.g., Kenni.is)
- Need custom claims in Firebase tokens
- Need user profile storage in Firestore
- Want full control over authentication flow
- Security is critical (PKCE provides extra protection)

❌ **Use Firebase OIDC Provider when**:
- Provider doesn't require PKCE
- Standard OpenID Connect claims are sufficient
- Want simplest setup possible
- Don't need custom user profiles

## Performance Considerations

**Latency**: Manual OAuth adds ~500-1000ms vs Firebase OIDC
- Token exchange: ~300ms (HTTP request to provider)
- JWT verification: ~100ms (JWKS fetch + signature verification)
- Firestore write: ~100ms (user profile creation)
- Custom token creation: ~50ms (local signing)

**Cost**:
- Cloud Functions invocations: ~0.000001 requests
- Firestore writes: ~0.000001 per user per login
- Secret Manager access: ~0.000001 per invocation

**Optimization**:
- Cache JWKS (reduce verification latency)
- Use Cloud Functions Gen2 (faster cold starts)
- Deploy function in same region as users
- Use connection pooling for Firestore

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and solutions.

## Further Reading

- [RFC 7636: PKCE](https://datatracker.ietf.org/doc/html/rfc7636)
- [Firebase Custom Tokens](https://firebase.google.com/docs/auth/admin/create-custom-tokens)
- [OpenID Connect Core 1.0](https://openid.net/specs/openid-connect-core-1_0.html)
- [JWT Best Practices](https://datatracker.ietf.org/doc/html/rfc8725)
