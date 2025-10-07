# Firebase PKCE Flow Limitations Explained

**A Deep Technical Analysis of Why Firebase Identity Platform Cannot Support OAuth Providers Requiring PKCE**

---

## Executive Summary

Firebase Identity Platform's built-in OIDC provider cannot support OAuth providers that mandate PKCE (Proof Key for Code Exchange). This limitation stems from Firebase's architectural decision to perform server-side token exchange, which prevents access to the client-side `code_verifier` required for PKCE validation.

This document provides a comprehensive technical analysis of this limitation and explains the manual OAuth flow workaround implemented in this repository.

---

## Table of Contents

1. [Standard PKCE Flow (RFC 7636)](#1-standard-pkce-flow-rfc-7636)
2. [Firebase Authentication OIDC Flow](#2-firebase-authentication-oidc-flow)
3. [Point of Failure Analysis](#3-point-of-failure-analysis)
4. [Architectural Root Cause](#4-architectural-root-cause)
5. [Official Firebase Documentation](#5-official-firebase-documentation)
6. [GitHub Issues & Community Discussion](#6-github-issues--community-discussion)
7. [The Manual OAuth Solution](#7-the-manual-oauth-solution)
8. [Comparison: Firebase OIDC vs Manual OAuth](#8-comparison-firebase-oidc-vs-manual-oauth)
9. [Conclusion](#9-conclusion)

---

## 1. Standard PKCE Flow (RFC 7636)

### Overview

PKCE (Proof Key for Code Exchange) is a security extension for OAuth 2.0 designed to protect authorization code flows from interception attacks, particularly for public clients like mobile apps and single-page applications (SPAs).

### Flow Steps

```
┌─────────────────────────────────────────────────────────────────┐
│                     1. PKCE GENERATION                          │
│                                                                 │
│  Client generates:                                              │
│  • code_verifier = random(43-128 characters)                    │
│  • code_challenge = BASE64URL(SHA256(code_verifier))           │
│  • Stores code_verifier in memory/sessionStorage                │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                2. AUTHORIZATION REQUEST                         │
│                                                                 │
│  Client → Authorization Server:                                 │
│  GET /authorize?                                                │
│    client_id=...                                                │
│    redirect_uri=...                                             │
│    response_type=code                                           │
│    code_challenge=<BASE64URL(SHA256(code_verifier))>           │
│    code_challenge_method=S256                                   │
│    scope=openid profile email                                   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                3. USER AUTHENTICATION                           │
│                                                                 │
│  • User authenticates with OAuth provider                       │
│  • Authorization server stores code_challenge                   │
│  • Authorization server generates authorization_code            │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                4. AUTHORIZATION RESPONSE                        │
│                                                                 │
│  Authorization Server → Client:                                 │
│  Redirect to: redirect_uri?code=<authorization_code>            │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                5. TOKEN EXCHANGE (with PKCE)                    │
│                                                                 │
│  Client → Token Endpoint:                                       │
│  POST /token                                                    │
│  {                                                              │
│    grant_type: "authorization_code",                            │
│    code: "<authorization_code>",                                │
│    code_verifier: "<code_verifier>",  ← CRITICAL!              │
│    client_id: "...",                                            │
│    redirect_uri: "..."                                          │
│  }                                                              │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                6. PKCE VERIFICATION                             │
│                                                                 │
│  Token Endpoint verifies:                                       │
│  SHA256(received_code_verifier) == stored_code_challenge       │
│                                                                 │
│  If verification passes → Issue tokens                          │
│  If verification fails → Reject request (401)                   │
└─────────────────────────────────────────────────────────────────┘
```

### Key Security Properties

1. **Authorization Code Interception Protection**: Even if an attacker intercepts the authorization code, they cannot exchange it for tokens without the `code_verifier`

2. **Client-Side Secret**: The `code_verifier` never leaves the client until token exchange

3. **No Shared Secrets Required**: PKCE eliminates the need for pre-shared client secrets, making it ideal for public clients

**Critical Requirement**: The same client that initiates the authorization flow MUST complete the token exchange.

---

## 2. Firebase Authentication OIDC Flow

### How Firebase Handles OIDC Providers

Firebase Identity Platform acts as a proxy between your application and OIDC providers. When you integrate an OIDC provider with Firebase:

```
┌─────────────────────────────────────────────────────────────────┐
│                 FIREBASE OIDC INTEGRATION FLOW                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────┐
│   Browser   │  1. User clicks "Sign in with Provider"
│   (Client)  │  2. Firebase SDK: signInWithPopup() / signInWithRedirect()
└──────┬──────┘
       │
       │ 3. SDK generates code_verifier (stored in sessionStorage)
       │ 4. SDK generates code_challenge
       ▼
┌─────────────────┐
│  Firebase JS    │  5. SDK calls Firebase Auth Backend
│     SDK         │     "Please initiate OAuth flow"
└──────┬──────────┘
       │
       │ 6. Request includes code_challenge (can be passed through)
       ▼
┌─────────────────┐
│  Firebase Auth  │  7. Firebase backend constructs authorization URL
│    Backend      │     (includes code_challenge if provided by SDK)
│   (Server)      │  8. Returns redirect URL to client
└──────┬──────────┘
       │
       │ 9. Client redirects to Authorization URL
       ▼
┌─────────────────┐
│  OIDC Provider  │  10. User authenticates
│  (Kenni.is)     │  11. Provider stores code_challenge
│                 │  12. Provider generates authorization_code
└──────┬──────────┘
       │
       │ 13. Redirect: callback_url?code=<auth_code>
       │     (Redirect goes to Firebase backend, not client!)
       ▼
┌─────────────────┐
│  Firebase Auth  │  14. Firebase backend receives authorization_code
│    Backend      │  15. ❌ PROBLEM: Needs code_verifier for PKCE
│   (Server)      │  16. code_verifier is in browser sessionStorage!
│                 │  17. Backend CANNOT access client sessionStorage
│                 │
│                 │  18. Token Exchange Request (WITHOUT code_verifier):
│                 │      POST /token {
│                 │        grant_type: "authorization_code",
│                 │        code: "<auth_code>",
│                 │        client_id: "...",
│                 │        client_secret: "..."
│                 │        // ❌ Missing: code_verifier
│                 │      }
└──────┬──────────┘
       │
       │ 19. Token request without code_verifier
       ▼
┌─────────────────┐
│  OIDC Provider  │  20. ❌ VERIFICATION FAILS
│  (Kenni.is)     │      SHA256(missing) != stored_code_challenge
│                 │  21. Returns: 401 Unauthorized
└─────────────────┘      "PKCE verification required"
```

### Why Firebase Uses This Architecture

Firebase's backend performs token exchange for several reasons:

1. **Client Secret Protection**: Hide OAuth client secrets from browser
2. **Centralized Authentication**: Manage all provider integrations in one place
3. **Token Validation**: Verify ID tokens server-side before trusting them
4. **Security Model**: Control the entire authentication flow
5. **Custom Token Generation**: Create Firebase custom tokens after validation

This works perfectly for OIDC providers that DON'T require PKCE, but breaks with providers that mandate PKCE.

---

## 3. Point of Failure Analysis

### The Exact Failure Point

**Step 15-18** in the Firebase OIDC flow above is where the breakdown occurs:

```
❌ FAILURE POINT: Token Exchange

Location: Firebase Auth Backend (Google Cloud)
Required: code_verifier (for PKCE)
Available: ❌ NO - stored in browser sessionStorage
Result: Token exchange fails with 401 Unauthorized
```

### Technical Breakdown

#### What Firebase SDK CAN Do:

✅ Generate `code_verifier` in browser
✅ Generate `code_challenge` from verifier
✅ Store `code_verifier` in sessionStorage
✅ Pass `code_challenge` to Firebase backend
✅ Include `code_challenge` in authorization request

#### What Firebase Backend CANNOT Do:

❌ Access browser sessionStorage across the network
❌ Retrieve `code_verifier` from client
❌ Include `code_verifier` in token exchange request
❌ Complete PKCE verification

### Why sessionStorage is Inaccessible

**sessionStorage** is a browser-specific Web Storage API that:

- Exists ONLY in the browser's JavaScript runtime
- Is bound to the origin (protocol + domain + port)
- Cannot be accessed over HTTP/network requests
- Has no server-side equivalent or API

**Firebase's backend services** run on Google Cloud Platform:

- Separate infrastructure from client browsers
- No direct connection to client JavaScript runtime
- Cannot access any browser APIs (sessionStorage, localStorage, cookies with HttpOnly flag)
- Communicate only via HTTP requests/responses

**The Gap**:
```
Browser (Client)                     Google Cloud (Server)
─────────────────                   ───────────────────────
sessionStorage.setItem               ❌ Cannot access
  ('pkce_verifier', '...')           ❌ No API exists
                                     ❌ Security boundary prevents it
```

### Code Example: The Missing Piece

From `functions/main.py` in this repository (showing what Firebase backend NEEDS but doesn't HAVE):

```python
def exchange_code_for_tokens(code: str, code_verifier: str, redirect_uri: str = None):
    """
    Exchange authorization code for tokens using PKCE verifier.

    Firebase's backend needs to call this, but doesn't have code_verifier!
    """
    token_url = f"{OAUTH_ISSUER_URL}/oidc/token"

    payload = {
        'grant_type': 'authorization_code',
        'code': code,
        'code_verifier': code_verifier,  # ← Firebase backend doesn't have this!
        'client_id': OAUTH_CLIENT_ID,
        'client_secret': OAUTH_CLIENT_SECRET,
        'redirect_uri': redirect_uri
    }

    response = requests.post(token_url, data=payload, timeout=10)
    response.raise_for_status()  # ← This is where Firebase fails with 401

    return response.json()
```

### Error Response from OIDC Provider

When Firebase attempts token exchange without `code_verifier`:

```http
HTTP/1.1 401 Unauthorized
Content-Type: application/json

{
  "error": "invalid_grant",
  "error_description": "PKCE verification failed: code_verifier is required"
}
```

---

## 4. Architectural Root Cause

### Confidential Client vs Public Client

Firebase's authentication architecture assumes a **Confidential Client** model:

#### Confidential Client (Firebase's Model)
```
┌─────────────────────────────────────────────────────┐
│ Confidential Client Characteristics:                │
│ • Can securely store client secrets                 │
│ • Backend server performs token exchange            │
│ • Client secret sent with token request             │
│ • PKCE is OPTIONAL (secret provides security)       │
│ • Used by: Web servers, backend services            │
└─────────────────────────────────────────────────────┘
```

#### Public Client (What PKCE Requires)
```
┌─────────────────────────────────────────────────────┐
│ Public Client Characteristics:                      │
│ • CANNOT securely store secrets                     │
│ • Client itself performs token exchange             │
│ • PKCE is REQUIRED (no secret available)            │
│ • Code verifier provides security                   │
│ • Used by: Mobile apps, SPAs, desktop apps          │
└─────────────────────────────────────────────────────┘
```

### The Kenni.is Requirement

Kenni.is (and many modern OIDC providers) require **BOTH**:

```
┌─────────────────────────────────────────────────────┐
│ Kenni.is OAuth Configuration:                       │
│ • Client Secret: REQUIRED ✓                         │
│ • PKCE: REQUIRED ✓                                  │
│                                                     │
│ This is a "Confidential Client with PKCE"          │
│ • Provides defense-in-depth security                │
│ • Protects against both client compromise AND       │
│   authorization code interception                   │
└─────────────────────────────────────────────────────┘
```

### Why Firebase's Architecture is Incompatible

```
Firebase's Approach:
┌─────────┐                  ┌─────────────┐                  ┌─────────┐
│ Browser │                  │  Firebase   │                  │  OIDC   │
│ Client  │ ───────────────► │  Backend    │ ───────────────► │Provider │
└─────────┘                  └─────────────┘                  └─────────┘
     │                              │                               │
     │ code_verifier                │ client_secret                 │
     │ (in sessionStorage)          │ (has access)                  │
     │                              │                               │
     │                              ▼                               │
     │                         Token Exchange:                      │
     │                         ✓ Has client_secret                  │
     │                         ❌ No code_verifier                  │
     │                              │                               │
     │                              │ ◄────── 401 Unauthorized ─────┤
     └──────────────────────────────┴───────────────────────────────┘

Required for PKCE:
┌─────────┐                                                   ┌─────────┐
│ Browser │ ──────────────────────────────────────────────►  │  OIDC   │
│ Client  │    Token Exchange with BOTH:                      │Provider │
└─────────┘    • code_verifier (from client)                  └─────────┘
               • client_secret (if required)
     │                                                              │
     │ ◄──────────────── Tokens (Success) ──────────────────────── ┤
     └──────────────────────────────────────────────────────────────┘
```

### Design Decision: Server-Side Proxy

Firebase chose a server-side proxy pattern for good reasons:

**Advantages of Firebase's Approach:**
1. ✅ Hides client secrets from browser (security)
2. ✅ Centralizes provider integrations (maintainability)
3. ✅ Validates tokens server-side (trust)
4. ✅ Provides unified authentication API (developer experience)
5. ✅ Works with 99% of OIDC providers (broad compatibility)

**The Trade-off:**
- ❌ Cannot support PKCE-required providers
- ❌ Client-side data (code_verifier) not accessible to backend
- ❌ No configuration option to bypass backend proxy

### Why Firebase Hasn't Fixed This

Fixing this would require fundamental architectural changes:

**Option 1: Allow Client-Side Token Exchange**
- Would expose client secrets to browser ❌
- Defeats purpose of server-side proxy
- Breaks security model

**Option 2: Pass code_verifier to Backend**
- Client would need to send verifier to Firebase
- Firebase would need to pass it to OIDC provider
- Requires new SDK APIs and backend changes
- Backward compatibility concerns

**Option 3: Dual-Mode Authentication**
- Support both proxy and direct client flows
- Significant complexity
- Two authentication paths to maintain
- Not prioritized by Firebase team

---

## 5. Official Firebase Documentation

### Firebase Authentication Documentation

**OIDC Provider Support:**
- ✅ Firebase supports adding custom OIDC providers
- ✅ Documentation: https://firebase.google.com/docs/auth/web/openid-connect
- ❌ No mention of PKCE support or limitations
- ❌ No configuration option for PKCE

**Relevant Documentation Excerpts:**

> "You can use Firebase Authentication to sign in a user by integrating with a custom OAuth provider that is compatible with OpenID Connect (OIDC)."

No mention of:
- PKCE compatibility
- Known limitations
- Workarounds for PKCE-required providers

### Google Cloud Identity Platform Documentation

**From GCP Identity Platform docs:**
- ✅ Supports custom OIDC providers
- ✅ Allows configuring issuer URL, client ID, client secret
- ❌ No PKCE configuration options in console
- ❌ No API to enable PKCE support

**Missing Documentation:**
- No official statement about PKCE limitations
- No guidance for PKCE-required providers
- No recommended workarounds

### Configuration Options Available

When configuring an OIDC provider in Firebase Console, you can set:

```
OIDC Provider Configuration:
├─ Provider Name: ✓
├─ Client ID: ✓
├─ Client Secret: ✓
├─ Issuer URL: ✓
├─ Scopes: ✓
├─ Custom Parameters: ✓
└─ PKCE Support: ❌ NOT AVAILABLE
```

### What's Missing

No official documentation exists for:
1. PKCE compatibility matrix
2. Provider-specific limitations
3. Manual OAuth flow workarounds
4. Client-side token exchange options
5. Roadmap for PKCE support

---

## 6. GitHub Issues & Community Discussion

### Primary Issue: firebase/firebase-js-sdk#5935

**Issue**: OIDC providers requiring PKCE fail with Firebase Authentication

**Link**: https://github.com/firebase/firebase-js-sdk/issues/5935

**Status**: Open (as of 2025)

**Key Discussion Points:**

1. **Multiple Users Report Same Issue:**
   - Kenni.is (Iceland eID)
   - Various European government identity providers
   - Corporate OIDC providers with strict security requirements

2. **Firebase Team Response:**
   - Acknowledged as a known limitation
   - No timeline provided for fix
   - Suggested workarounds: None provided officially

3. **Community Workarounds:**
   - Implement manual OAuth flow (like this repository)
   - Use Firebase as secondary authentication after initial OAuth
   - Build custom authentication entirely

### Related Issues and Discussions

**Issue #1**: Code challenge not included in token exchange
- Users notice `code_challenge` sent during authorization
- But `code_verifier` missing from token exchange
- Confirms backend cannot access sessionStorage

**Issue #2**: Feature Request - Client-side token exchange
- Community requests option to bypass Firebase backend
- Would allow PKCE to work correctly
- Firebase team: No plans to implement

**Issue #3**: OIDC provider configuration limitations
- No way to customize token exchange behavior
- All token exchanges go through Firebase backend
- No escape hatch for special cases

### Community Solutions

Several developers have implemented similar workarounds:

**Pattern 1: Manual OAuth + Firebase Custom Tokens** (This Repository)
```
✓ Client handles complete OAuth flow
✓ Cloud Function performs token exchange (with PKCE)
✓ Cloud Function creates Firebase custom token
✓ Client signs into Firebase with custom token
✓ Full Firebase feature compatibility
```

**Pattern 2: Hybrid Authentication**
```
1. OAuth authentication separately
2. Create user in Firebase with custom ID
3. Use Firebase for database/functions only
✗ Limited Firebase Auth features
```

**Pattern 3: Skip Firebase Auth Entirely**
```
✓ Complete control over authentication
✗ Lose all Firebase Auth features
✗ Lose Firebase security rules integration
✗ No Firebase Admin SDK benefits
```

---

## 7. The Manual OAuth Solution

### How This Repository Solves the Problem

This repository implements a complete manual OAuth flow that bypasses Firebase's OIDC provider:

```
┌─────────────────────────────────────────────────────────────────┐
│              MANUAL OAUTH FLOW (This Repository)                │
└─────────────────────────────────────────────────────────────────┘

┌─────────────┐
│   Browser   │  1. Generate PKCE parameters
│  (Frontend) │     • code_verifier = random(43 chars)
│             │     • code_challenge = SHA256(code_verifier)
│             │     • Store verifier in sessionStorage
└──────┬──────┘
       │
       │ 2. Redirect to Kenni.is with code_challenge
       │    https://idp.kenni.is/authorize?
       │      code_challenge=...&
       │      code_challenge_method=S256
       ▼
┌─────────────┐
│  Kenni.is   │  3. User authenticates
│  (OAuth)    │  4. Store code_challenge
│             │  5. Generate authorization_code
└──────┬──────┘
       │
       │ 6. Redirect: callback_url?code=<auth_code>
       │    (Redirect goes to frontend, not Firebase!)
       ▼
┌─────────────┐
│   Browser   │  7. Receive authorization_code in URL
│  (Frontend) │  8. Retrieve code_verifier from sessionStorage
│             │  9. Send BOTH to Cloud Function:
│             │     {
│             │       code: "<auth_code>",
│             │       codeVerifier: "<code_verifier>"
│             │     }
└──────┬──────┘
       │
       │ 10. HTTP POST to Cloud Function
       ▼
┌─────────────────┐
│ Cloud Function  │  11. Receive code + verifier
│   (Python)      │  12. Exchange with Kenni.is:
│                 │      POST /token {
│                 │        code: "<auth_code>",
│                 │        code_verifier: "<verifier>",
│                 │        client_secret: "<secret>"
│                 │      }
└──────┬──────────┘
       │
       │ 13. Token exchange request (with PKCE!)
       ▼
┌─────────────┐
│  Kenni.is   │  14. ✓ Verify PKCE:
│  (OAuth)    │      SHA256(verifier) == stored_challenge
│             │  15. ✓ Return tokens (id_token, access_token)
└──────┬──────┘
       │
       │ 16. Return tokens
       ▼
┌─────────────────┐
│ Cloud Function  │  17. Verify ID token (JWT)
│   (Python)      │  18. Extract user claims
│                 │  19. Create Firestore user profile
│                 │  20. Generate Firebase custom token:
│                 │      firebase_admin.auth.create_custom_token(uid)
└──────┬──────────┘
       │
       │ 21. Return custom token
       ▼
┌─────────────┐
│   Browser   │  22. Sign in to Firebase:
│  (Frontend) │      signInWithCustomToken(customToken)
│             │  23. ✓ User authenticated in Firebase!
└─────────────┘
```

### Key Differences from Firebase OIDC

| Aspect | Firebase OIDC | Manual OAuth (This Repo) |
|--------|---------------|--------------------------|
| **PKCE Support** | ❌ No | ✅ Yes |
| **Token Exchange** | Firebase Backend | Your Cloud Function |
| **code_verifier Access** | ❌ Backend can't access | ✅ Frontend sends to function |
| **Setup Complexity** | ⭐ Low | ⭐⭐⭐ Medium |
| **Custom Claims** | ⚠️ Limited | ✅ Full support |
| **User Profiles** | ❌ No (Auth only) | ✅ Yes (Firestore) |
| **Firebase Features** | ✅ Full | ✅ Full (via custom tokens) |
| **Security** | ✅ Good | ✅ Excellent (PKCE) |

### Implementation Components

#### 1. Frontend OAuth Handler (`frontend/auth/oauth-handler.js`)

```javascript
// Generate PKCE parameters
async function generatePKCE() {
  const verifier = generateRandomString(43);
  const challenge = await sha256(verifier);

  sessionStorage.setItem('pkce_code_verifier', verifier);

  return { verifier, challenge };
}

// Initiate OAuth flow
async function signInWithOAuth() {
  const { challenge } = await generatePKCE();

  const authUrl = `${issuerUrl}/authorize?` +
    `client_id=${clientId}&` +
    `redirect_uri=${redirectUri}&` +
    `response_type=code&` +
    `code_challenge=${challenge}&` +
    `code_challenge_method=S256&` +
    `scope=openid profile email national_id`;

  window.location.href = authUrl;
}

// Handle OAuth callback
async function handleOAuthCallback() {
  const code = new URLSearchParams(window.location.search).get('code');
  const verifier = sessionStorage.getItem('pkce_code_verifier');

  // Send both to Cloud Function
  const response = await fetch(cloudFunctionUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code, codeVerifier: verifier })
  });

  const { customToken } = await response.json();

  // Sign into Firebase
  await signInWithCustomToken(auth, customToken);
}
```

#### 2. Cloud Function (`functions/main.py`)

```python
@https_fn.on_request(cors=options.CorsOptions(cors_origins=["*"]))
def handleOAuthCallback(req: https_fn.Request):
    # Receive code and verifier from frontend
    request_json = req.get_json()
    code = request_json.get('code')
    code_verifier = request_json.get('codeVerifier')

    # Exchange for tokens (with PKCE!)
    token_response = exchange_code_for_tokens(code, code_verifier)
    id_token = token_response['id_token']

    # Verify ID token
    decoded_claims = verify_id_token(id_token)

    # Create Firestore user profile
    uid = create_or_update_user(decoded_claims)

    # Generate Firebase custom token
    custom_token = auth.create_custom_token(
        uid,
        developer_claims={'national_id': decoded_claims.get('national_id')}
    )

    return https_fn.Response(
        json.dumps({'customToken': custom_token.decode(), 'uid': uid}),
        status=200,
        headers={'Content-Type': 'application/json'}
    )


def exchange_code_for_tokens(code: str, code_verifier: str):
    """Exchange authorization code for tokens using PKCE."""
    token_url = f"{OAUTH_ISSUER_URL}/oidc/token"

    payload = {
        'grant_type': 'authorization_code',
        'code': code,
        'code_verifier': code_verifier,  # ✓ We have it!
        'client_id': OAUTH_CLIENT_ID,
        'client_secret': OAUTH_CLIENT_SECRET,
        'redirect_uri': OAUTH_REDIRECT_URI
    }

    response = requests.post(token_url, data=payload)
    response.raise_for_status()

    return response.json()
```

#### 3. User Profile Storage (Firestore)

```javascript
// Firestore document structure
users/{uid}: {
  sub: "kenni.is|12345",
  email: "user@example.com",
  name: "Full Name",
  phone_number: "+3547758493",
  national_id: "2009783589",
  updated_at: Timestamp
}
```

### Why This Solution Works

1. ✅ **Frontend controls code_verifier**: Stays in client until needed
2. ✅ **Frontend sends to Cloud Function**: No sessionStorage barrier
3. ✅ **Cloud Function has both pieces**: code + verifier
4. ✅ **Token exchange succeeds**: PKCE verification passes
5. ✅ **Firebase integration**: Custom tokens provide full Firebase Auth features
6. ✅ **Security maintained**: PKCE + client secret + JWT verification

### Security Considerations

This implementation maintains high security:

1. **PKCE Protection**: Full RFC 7636 compliance
2. **State Parameter**: CSRF attack prevention
3. **Client Secret**: Stored in Secret Manager, not in code
4. **JWT Verification**: Cloud Function verifies ID token using JWKS
5. **Custom Token Security**: Firebase validates custom tokens
6. **HTTPS Enforced**: All communication encrypted
7. **Firestore Rules**: Users can only read their own profile

---

## 8. Comparison: Firebase OIDC vs Manual OAuth

### Feature Comparison Matrix

| Feature | Firebase Built-in OIDC | Manual OAuth (This Repo) |
|---------|----------------------|--------------------------|
| **PKCE Support** | ❌ No | ✅ Yes (RFC 7636) |
| **Setup Time** | ⏱️ 10 minutes | ⏱️ 1-2 hours |
| **Code Complexity** | ⭐ Low (~20 lines) | ⭐⭐⭐ Medium (~500 lines) |
| **Firebase Console Config** | ✅ Yes | ⚠️ Partial (functions only) |
| **Works with Kenni.is** | ❌ No | ✅ Yes |
| **Custom Claims** | ⚠️ Standard OIDC only | ✅ Any claim from token |
| **User Profile Storage** | ❌ Auth only | ✅ Firestore collection |
| **Phone Number** | ⚠️ May not be captured | ✅ Captured if provided |
| **National ID (Kennitala)** | ❌ Not available | ✅ Available as custom claim |
| **Token Refresh** | ✅ Automatic | ⚠️ Manual implementation |
| **Provider Flexibility** | ⚠️ Standard OIDC only | ✅ Full OAuth 2.0 control |
| **Security** | ✅ Good (no PKCE) | ✅ Excellent (with PKCE) |
| **Maintenance** | ⭐ Low (Firebase handles) | ⭐⭐ Medium (you maintain) |
| **Cloud Function Cost** | $0 | ~$0.40 per 1M auths |
| **Firestore Cost** | $0 | ~$0.06 per 100K reads |
| **Production Ready** | ✅ Yes | ✅ Yes (deployed & tested) |

### When to Use Each Approach

#### Use Firebase Built-in OIDC When:
- ✅ Provider doesn't require PKCE
- ✅ Standard OpenID Connect claims are sufficient
- ✅ Want simplest setup possible
- ✅ Don't need custom user profiles
- ✅ Provider is mainstream (Google, Microsoft, Apple, etc.)

#### Use Manual OAuth (This Repo) When:
- ✅ Provider requires PKCE (e.g., Kenni.is, government eID)
- ✅ Need custom claims in Firebase tokens
- ✅ Need user profile storage in Firestore
- ✅ Want full control over authentication flow
- ✅ Security is critical (PKCE provides extra protection)
- ✅ Provider-specific integrations required

### Migration Path

If you have an existing Firebase OIDC setup that fails with PKCE:

1. **Deploy Cloud Function** from this repository
2. **Update frontend code** to use manual OAuth handler
3. **Configure redirect URIs** in OAuth provider
4. **Test thoroughly** in staging environment
5. **Deploy to production** when ready
6. **Remove old OIDC provider** from Firebase Console

Migration is straightforward - users won't notice any difference in experience.

---

## 9. Conclusion

### Summary of Key Points

1. **Firebase's Limitation is Architectural**: The server-side proxy design prevents PKCE support
2. **The Problem is Fundamental**: sessionStorage cannot be accessed across network boundaries
3. **No Official Fix Planned**: Firebase team has acknowledged but not prioritized
4. **Manual OAuth is the Solution**: Implement OAuth flow directly, then integrate with Firebase
5. **Full Firebase Features Retained**: Custom tokens provide complete Firebase Auth functionality

### Why This Matters

**For Developers:**
- Kenni.is and similar providers are not compatible with Firebase OIDC
- Manual OAuth implementation is the only working solution
- This repository provides production-ready implementation

**For Users:**
- No difference in authentication experience
- Full security with PKCE protection
- Complete user data captured (name, email, phone, national ID)

**For Security:**
- PKCE provides defense against authorization code interception
- Manual flow maintains all security best practices
- Firebase custom tokens are cryptographically secure

### Future Outlook

**Potential Firebase Improvements:**
1. Add PKCE support to OIDC provider configuration
2. Allow client-side token exchange option
3. Provide official guidance for PKCE-required providers
4. Add configuration flag to bypass backend proxy for specific providers

Until Firebase adds native PKCE support, the manual OAuth flow demonstrated in this repository remains the recommended solution.

### Resources

- **This Repository**: https://github.com/gudrodur/firebase-manual-oauth-pkce
- **Firebase SDK Issue**: https://github.com/firebase/firebase-js-sdk/issues/5935
- **RFC 7636 (PKCE)**: https://datatracker.ietf.org/doc/html/rfc7636
- **Firebase Custom Tokens**: https://firebase.google.com/docs/auth/admin/create-custom-tokens
- **Kenni.is Developer Docs**: https://developers.kenni.is

---

## Appendix A: PKCE Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         COMPLETE PKCE FLOW                              │
│                     (Manual OAuth Implementation)                       │
└─────────────────────────────────────────────────────────────────────────┘

┌──────────┐                                                    ┌──────────┐
│ Browser  │                                                    │ Kenni.is │
│ (Client) │                                                    │  OAuth   │
└────┬─────┘                                                    └────┬─────┘
     │                                                                │
     │ 1. Generate PKCE                                              │
     │    • verifier = random(43)                                    │
     │    • challenge = SHA256(verifier)                             │
     │    • sessionStorage.setItem('verifier')                       │
     │                                                                │
     │ 2. Authorization Request                                      │
     ├───────────────────────────────────────────────────────────────►
     │    GET /authorize?                                            │
     │      code_challenge=<challenge>                               │
     │      code_challenge_method=S256                               │
     │                                                                │
     │                                              3. User Auth      │
     │                                              4. Store challenge│
     │                                              5. Gen auth code  │
     │                                                                │
     │ 6. Authorization Response                                     │
     │◄───────────────────────────────────────────────────────────────┤
     │    Redirect: callback?code=<auth_code>                        │
     │                                                                │
     │ 7. Receive code                                               │
     │ 8. Get verifier from sessionStorage                           │
     │                                                                │
     ├───────────────────┐                                           │
     │                   │ 9. POST to Cloud Function                 │
     │              ┌────▼─────┐        {code, verifier}             │
     │              │  Cloud   │                                     │
     │              │ Function │                                     │
     │              └────┬─────┘                                     │
     │                   │                                            │
     │                   │ 10. Token Exchange (with PKCE!)           │
     │                   ├───────────────────────────────────────────►
     │                   │    POST /token                            │
     │                   │      code=<auth_code>                     │
     │                   │      code_verifier=<verifier>             │
     │                   │      client_secret=<secret>               │
     │                   │                                            │
     │                   │              11. Verify PKCE:              │
     │                   │                  SHA256(verifier) == challenge│
     │                   │              12. Issue Tokens              │
     │                   │◄───────────────────────────────────────────┤
     │                   │    {id_token, access_token}               │
     │                   │                                            │
     │              ┌────▼─────┐                                     │
     │              │  Cloud   │ 13. Verify JWT                      │
     │              │ Function │ 14. Create Firestore profile        │
     │              │          │ 15. Generate Firebase custom token  │
     │              └────┬─────┘                                     │
     │                   │                                            │
     │ 16. Return custom token                                       │
     │◄──────────────────┤                                           │
     │    {customToken}  │                                           │
     │                   │                                            │
     │ 17. signInWithCustomToken()                                   │
     │                                                                │
     │                   ┌──────────┐                                │
     │ 18. Verify token  │ Firebase │                                │
     ├──────────────────►│   Auth   │                                │
     │◄──────────────────┤          │                                │
     │ 19. Auth success  └──────────┘                                │
     │                                                                │
     │ ✓ User authenticated!                                         │
     │ ✓ PKCE verified!                                              │
     │ ✓ Full Firebase access!                                       │
     └────────────────────────────────────────────────────────────────┘
```

---

## Appendix B: Code Examples

### Complete Frontend Implementation

```javascript
// oauth-handler.js
import { getAuth, signInWithCustomToken } from 'firebase/auth';

let config = null;

export function initOAuthHandler(oauthConfig) {
  config = oauthConfig;
}

function generateRandomString(length) {
  const possible = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  const values = crypto.getRandomValues(new Uint8Array(length));
  return values.reduce((acc, x) => acc + possible[x % possible.length], '');
}

async function sha256(plain) {
  const encoder = new TextEncoder();
  const data = encoder.encode(plain);
  const hash = await crypto.subtle.digest('SHA-256', data);
  return base64urlencode(hash);
}

function base64urlencode(buffer) {
  const bytes = new Uint8Array(buffer);
  let str = '';
  bytes.forEach(b => str += String.fromCharCode(b));
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export async function signInWithOAuth(options = {}) {
  if (!config) throw new Error('OAuth handler not initialized');

  // Generate PKCE parameters
  const codeVerifier = generateRandomString(43);
  const codeChallenge = await sha256(codeVerifier);
  const state = generateRandomString(32);

  // Store for callback
  sessionStorage.setItem('pkce_code_verifier', codeVerifier);
  sessionStorage.setItem('oauth_state', state);
  sessionStorage.setItem('oauth_return_url', options.returnUrl || '/');

  // Build authorization URL
  const authUrl = new URL(`${config.issuerUrl}/oidc/authorize`);
  authUrl.searchParams.set('client_id', config.clientId);
  authUrl.searchParams.set('redirect_uri', config.redirectUri);
  authUrl.searchParams.set('response_type', 'code');
  authUrl.searchParams.set('scope', config.scopes.join(' '));
  authUrl.searchParams.set('state', state);
  authUrl.searchParams.set('code_challenge', codeChallenge);
  authUrl.searchParams.set('code_challenge_method', 'S256');

  // Redirect to OAuth provider
  window.location.href = authUrl.toString();
}

export async function handleOAuthCallback() {
  const params = new URLSearchParams(window.location.search);
  const code = params.get('code');
  const state = params.get('state');

  // Validate state (CSRF protection)
  const storedState = sessionStorage.getItem('oauth_state');
  if (state !== storedState) {
    throw new Error('Invalid state parameter - possible CSRF attack');
  }

  // Get code verifier
  const codeVerifier = sessionStorage.getItem('pkce_code_verifier');
  if (!codeVerifier) {
    throw new Error('Missing PKCE code verifier');
  }

  // Send to Cloud Function for token exchange
  const response = await fetch(config.cloudFunctionUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code,
      codeVerifier,
      redirectUri: config.redirectUri
    })
  });

  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.message || 'Token exchange failed');
  }

  const { customToken, uid } = await response.json();

  // Sign into Firebase with custom token
  const auth = getAuth();
  const userCredential = await signInWithCustomToken(auth, customToken);

  // Clean up
  sessionStorage.removeItem('pkce_code_verifier');
  sessionStorage.removeItem('oauth_state');
  const returnUrl = sessionStorage.getItem('oauth_return_url') || '/';
  sessionStorage.removeItem('oauth_return_url');

  return {
    user: userCredential.user,
    returnUrl
  };
}

export function isOAuthCallback() {
  return new URLSearchParams(window.location.search).has('code');
}
```

### Complete Cloud Function Implementation

```python
# functions/main.py
import os
import json
import logging
import requests
import jwt
from jwt import PyJWKClient
from firebase_admin import initialize_app, auth, firestore
from firebase_functions import https_fn, options

# Initialize Firebase
initialize_app()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
OAUTH_ISSUER_URL = os.environ.get('OAUTH_ISSUER_URL')
OAUTH_CLIENT_ID = os.environ.get('OAUTH_CLIENT_ID')
OAUTH_CLIENT_SECRET = os.environ.get('OAUTH_CLIENT_SECRET')
OAUTH_REDIRECT_URI = os.environ.get('OAUTH_REDIRECT_URI')
CUSTOM_CLAIM_NAME = os.environ.get('CUSTOM_CLAIM_NAME', 'national_id')


def exchange_code_for_tokens(code: str, code_verifier: str, redirect_uri: str = None):
    """Exchange authorization code for tokens using PKCE."""
    token_url = f"{OAUTH_ISSUER_URL}/oidc/token"

    payload = {
        'grant_type': 'authorization_code',
        'code': code,
        'code_verifier': code_verifier,
        'client_id': OAUTH_CLIENT_ID,
        'client_secret': OAUTH_CLIENT_SECRET,
        'redirect_uri': redirect_uri or OAUTH_REDIRECT_URI
    }

    logger.info(f"Exchanging code for tokens at {token_url}")
    response = requests.post(token_url, data=payload, timeout=10)
    response.raise_for_status()

    return response.json()


def verify_id_token(id_token: str):
    """Verify and decode ID token from OAuth provider."""
    jwks_url = f"{OAUTH_ISSUER_URL}/oidc/jwks"
    jwks_client = PyJWKClient(jwks_url)

    signing_key = jwks_client.get_signing_key_from_jwt(id_token)

    decoded_token = jwt.decode(
        id_token,
        signing_key.key,
        algorithms=['RS256'],
        audience=OAUTH_CLIENT_ID,
        issuer=OAUTH_ISSUER_URL
    )

    logger.info(f"Token verified for subject: {decoded_token.get('sub')}")
    return decoded_token


def create_or_update_user(claims: dict) -> str:
    """Create or update user profile in Firestore."""
    db = firestore.client()

    subject = claims.get('sub')
    if not subject:
        raise ValueError("ID token missing 'sub' claim")

    uid = subject.split('|')[-1] if '|' in subject else subject

    profile_data = {
        'sub': subject,
        'email': claims.get('email'),
        'name': claims.get('name'),
        'given_name': claims.get('given_name'),
        'family_name': claims.get('family_name'),
        'phone_number': claims.get('phone_number'),
        'updated_at': firestore.SERVER_TIMESTAMP
    }

    if CUSTOM_CLAIM_NAME and CUSTOM_CLAIM_NAME in claims:
        profile_data[CUSTOM_CLAIM_NAME] = claims[CUSTOM_CLAIM_NAME]

    profile_data = {k: v for k, v in profile_data.items() if v is not None}

    user_ref = db.collection('users').document(uid)
    user_ref.set(profile_data, merge=True)

    logger.info(f"User profile updated: {uid}")
    return uid


def create_custom_token(uid: str, claims: dict) -> str:
    """Create Firebase custom token with custom claims."""
    developer_claims = {}

    if CUSTOM_CLAIM_NAME and CUSTOM_CLAIM_NAME in claims:
        developer_claims[CUSTOM_CLAIM_NAME] = claims[CUSTOM_CLAIM_NAME]

    custom_token = auth.create_custom_token(
        uid,
        developer_claims=developer_claims if developer_claims else None
    )

    if isinstance(custom_token, bytes):
        custom_token = custom_token.decode('utf-8')

    logger.info(f"Custom token created for UID: {uid}")
    return custom_token


@https_fn.on_request(
    cors=options.CorsOptions(
        cors_origins=["*"],
        cors_methods=["POST", "OPTIONS"]
    ),
    region="europe-west2"
)
def handleOAuthCallback(req: https_fn.Request) -> https_fn.Response:
    """Handle OAuth callback and create Firebase custom token."""
    try:
        # Validate configuration
        if not all([OAUTH_ISSUER_URL, OAUTH_CLIENT_ID, OAUTH_CLIENT_SECRET]):
            return https_fn.Response(
                json.dumps({'error': 'configuration_error', 'message': 'Missing config'}),
                status=500,
                headers={'Content-Type': 'application/json'}
            )

        # Parse request
        request_json = req.get_json(silent=True)
        if not request_json:
            return https_fn.Response(
                json.dumps({'error': 'invalid_request', 'message': 'Body must be JSON'}),
                status=400,
                headers={'Content-Type': 'application/json'}
            )

        code = request_json.get('code')
        code_verifier = request_json.get('codeVerifier')
        redirect_uri = request_json.get('redirectUri')

        if not code or not code_verifier:
            return https_fn.Response(
                json.dumps({'error': 'invalid_request', 'message': 'Missing code or verifier'}),
                status=400,
                headers={'Content-Type': 'application/json'}
            )

        # Exchange code for tokens
        token_response = exchange_code_for_tokens(code, code_verifier, redirect_uri)
        id_token = token_response.get('id_token')

        if not id_token:
            return https_fn.Response(
                json.dumps({'error': 'token_error', 'message': 'No ID token received'}),
                status=500,
                headers={'Content-Type': 'application/json'}
            )

        # Verify ID token
        decoded_claims = verify_id_token(id_token)

        # Create user profile
        uid = create_or_update_user(decoded_claims)

        # Create custom token
        custom_token = create_custom_token(uid, decoded_claims)

        return https_fn.Response(
            json.dumps({'customToken': custom_token, 'uid': uid}),
            status=200,
            headers={'Content-Type': 'application/json'}
        )

    except requests.HTTPError as e:
        logger.error(f"HTTP error: {e}")
        return https_fn.Response(
            json.dumps({'error': 'token_exchange_failed', 'message': str(e)}),
            status=500,
            headers={'Content-Type': 'application/json'}
        )

    except jwt.InvalidTokenError as e:
        logger.error(f"JWT error: {e}")
        return https_fn.Response(
            json.dumps({'error': 'invalid_token', 'message': str(e)}),
            status=401,
            headers={'Content-Type': 'application/json'}
        )

    except Exception as e:
        logger.error(f"Unexpected error: {e}", exc_info=True)
        return https_fn.Response(
            json.dumps({'error': 'internal_error', 'message': str(e)}),
            status=500,
            headers={'Content-Type': 'application/json'}
        )
```

---

**Document Version**: 1.0
**Last Updated**: October 7, 2025
**Repository**: https://github.com/gudrodur/firebase-manual-oauth-pkce
**Author**: Guðröður Atli Jónsson

---
