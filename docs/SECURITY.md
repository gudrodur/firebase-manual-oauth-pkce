# Security Best Practices

This document outlines security considerations when implementing Firebase Manual OAuth with PKCE.

## PKCE (Proof Key for Code Exchange)

### Why PKCE Matters

PKCE protects against authorization code interception attacks:

1. **Without PKCE**: Attacker intercepts authorization code → exchanges for tokens ❌
2. **With PKCE**: Attacker intercepts code → can't exchange without verifier ✅

### PKCE Implementation Requirements

✅ **DO**:
- Use cryptographically secure random number generation (`crypto.getRandomValues()`)
- Generate code_verifier with minimum 43 characters (128 bits entropy)
- Use S256 code_challenge_method (SHA-256 hash)
- Clear code_verifier from sessionStorage after use
- Validate code_challenge on server

❌ **DON'T**:
- Use `Math.random()` for generating verifier (not secure!)
- Store code_verifier in localStorage (survives sessions)
- Reuse code_verifier across multiple login attempts
- Send code_verifier in URL parameters (visible in logs)

## State Parameter (CSRF Protection)

### Why State Matters

The state parameter prevents Cross-Site Request Forgery (CSRF) attacks:

**Attack scenario without state**:
1. Attacker initiates OAuth flow with their account
2. Attacker captures the callback URL
3. Attacker tricks victim into visiting callback URL
4. Victim gets logged into attacker's account

**Protection with state**:
1. Client generates random state value
2. Client stores state in sessionStorage
3. OAuth provider returns state in callback
4. Client verifies: received state == stored state
5. If mismatch, reject callback

### State Implementation

```javascript
// Generate state
const state = generateRandomString(); // Crypto-secure random

// Store in sessionStorage
sessionStorage.setItem('oauth_state', state);

// Include in authorization URL
const authUrl = `${issuerUrl}/auth?state=${state}&...`;

// Verify on callback
const receivedState = new URLSearchParams(window.location.search).get('state');
const storedState = sessionStorage.getItem('oauth_state');

if (receivedState !== storedState) {
  throw new Error('Invalid state - possible CSRF attack');
}
```

## Client Secret Management

### Storage

✅ **DO**:
- Store client secret in Google Cloud Secret Manager
- Use environment variables in Cloud Functions
- Rotate secrets periodically
- Grant minimal access (secretAccessor role only)
- Use separate secrets for dev/staging/production

❌ **DON'T**:
- Commit secrets to version control
- Store in .env files committed to git
- Hardcode in source files
- Share across multiple projects
- Expose in client-side code

### Access Control

```bash
# Create secret
echo -n "your-secret" | gcloud secrets create oauth-client-secret \
  --data-file=- \
  --replication-policy=automatic

# Grant access to Cloud Function only
PROJECT_NUMBER=$(gcloud projects describe PROJECT_ID --format="value(projectNumber)")
gcloud secrets add-iam-policy-binding oauth-client-secret \
  --member=serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com \
  --role=roles/secretmanager.secretAccessor
```

## JWT Verification

### Why Verify JWTs

The Cloud Function must verify ID tokens from OAuth providers to prevent:
- Token forgery
- Token replay attacks
- Token tampering
- Unauthorized access

### Verification Checklist

✅ **Verify**:
- Signature (using provider's JWKS)
- Algorithm (must be RS256, not none or HS256)
- Issuer (`iss` claim matches provider URL)
- Audience (`aud` claim matches client ID)
- Expiration (`exp` claim is in future)
- Not Before (`nbf` claim if present)
- Issued At (`iat` claim is reasonable)

### Implementation

```python
from jwt import PyJWKClient
import jwt

# Fetch JWKS from provider
jwks_url = f"{OAUTH_ISSUER_URL}/.well-known/jwks.json"
jwks_client = PyJWKClient(jwks_url)

# Get signing key
signing_key = jwks_client.get_signing_key_from_jwt(id_token)

# Verify and decode
decoded = jwt.decode(
    id_token,
    signing_key.key,
    algorithms=['RS256'],  # Only RS256!
    audience=OAUTH_CLIENT_ID,
    issuer=OAUTH_ISSUER_URL,
    leeway=60  # Allow 60s clock skew
)
```

### Common Vulnerabilities

❌ **CRITICAL**: Never accept `alg: none`
```python
# BAD - accepts unsigned tokens!
decoded = jwt.decode(id_token, verify=False)

# GOOD - requires signature
decoded = jwt.decode(id_token, signing_key.key, algorithms=['RS256'])
```

❌ **CRITICAL**: Never use HS256 with client secret
```python
# BAD - allows attacker to forge tokens if they know client secret
decoded = jwt.decode(id_token, client_secret, algorithms=['HS256'])

# GOOD - uses provider's public key
decoded = jwt.decode(id_token, signing_key.key, algorithms=['RS256'])
```

## Firebase Custom Tokens

### Security Properties

Firebase custom tokens are secure because:
- Signed with Firebase service account private key (only server has it)
- Short-lived (1 hour expiration)
- Validated by Firebase on sign-in
- Can include custom claims for authorization

### Best Practices

✅ **DO**:
- Create custom tokens server-side only (never in client)
- Include minimal claims (only what's needed for authorization)
- Validate user data before creating token
- Log token creation for audit trail
- Use service account with minimal permissions

❌ **DON'T**:
- Expose Firebase service account key
- Create tokens without verifying OAuth ID token first
- Include sensitive data in custom claims (tokens are not encrypted!)
- Reuse tokens (create fresh token for each sign-in)

### Custom Claims

```python
# ✅ GOOD - minimal, authorization-related claims
custom_token = auth.create_custom_token(
    uid,
    developer_claims={
        'role': 'member',
        'verified': True
    }
)

# ❌ BAD - sensitive data in claims
custom_token = auth.create_custom_token(
    uid,
    developer_claims={
        'password': 'secret123',  # Never!
        'credit_card': '1234-5678',  # Never!
        'ssn': '123-45-6789'  # Never!
    }
)
```

## HTTPS/TLS

### Requirements

All OAuth flows MUST use HTTPS:
- Authorization requests
- Token exchange
- Callback URLs
- Cloud Function URLs

### Validation

```bash
# ✅ HTTPS URLs only
https://idp.provider.com/auth
https://your-project.cloudfunctions.net/handleOAuthCallback

# ❌ HTTP URLs rejected
http://idp.provider.com/auth  # Insecure!
http://localhost/callback  # Only for local dev
```

### Certificate Validation

Python `requests` library validates certificates by default:

```python
# ✅ GOOD - validates certificate
response = requests.post(token_url, data=payload)

# ❌ BAD - disables validation!
response = requests.post(token_url, data=payload, verify=False)
```

## CORS Configuration

### Principle of Least Privilege

Only allow specific origins that need access:

```python
# ✅ GOOD - specific origins
cors=options.CorsOptions(
    cors_origins=[
        "https://your-app.com",
        "https://your-project.web.app"
    ],
    cors_methods=["POST", "OPTIONS"]
)

# ❌ BAD - allows any origin (unless public API)
cors=options.CorsOptions(
    cors_origins=["*"],
    cors_methods=["GET", "POST", "PUT", "DELETE"]
)
```

### Preflight Requests

Cloud Functions handle OPTIONS preflight automatically. No additional code needed.

## Input Validation

### Cloud Function Inputs

Always validate inputs from clients:

```python
# Validate request body exists
request_json = req.get_json(silent=True)
if not request_json:
    return error_response('invalid_request', 'Request body required')

# Validate required fields
code = request_json.get('code')
code_verifier = request_json.get('codeVerifier')

if not code or not code_verifier:
    return error_response('invalid_request', 'Missing code or codeVerifier')

# Validate field formats
if not isinstance(code, str) or len(code) > 1000:
    return error_response('invalid_request', 'Invalid code format')

if not isinstance(code_verifier, str) or len(code_verifier) != 43:
    return error_response('invalid_request', 'Invalid codeVerifier format')
```

### Sanitize User Data

```python
# Sanitize before storing in Firestore
profile_data = {
    'email': str(claims.get('email', '')).strip(),
    'name': str(claims.get('name', '')).strip()[:100],  # Limit length
}

# Remove None values
profile_data = {k: v for k, v in profile_data.items() if v is not None}
```

## Error Handling

### Don't Leak Secrets

❌ **BAD**:
```python
except Exception as e:
    return {'error': str(e)}  # May leak secrets!
```

✅ **GOOD**:
```python
except requests.HTTPError as e:
    logger.error(f"Token exchange failed: {e}")  # Log details
    return {
        'error': 'token_exchange_failed',
        'message': 'Failed to exchange authorization code'  # Generic message
    }
```

### Structured Logging

```python
# ✅ Log for debugging (server-side only)
logger.info(f"User authenticated: {claims.get('sub')}")
logger.debug(f"Token expires: {claims.get('exp')}")

# ❌ Don't log secrets
logger.info(f"Access token: {access_token}")  # Never!
logger.info(f"Client secret: {CLIENT_SECRET}")  # Never!
```

## Rate Limiting

### Cloud Functions

Cloud Functions has built-in quotas, but consider adding additional rate limiting:

```python
from functools import lru_cache
import time

# Simple in-memory rate limiter
request_counts = {}

def rate_limit(client_id: str, max_requests: int = 10, window: int = 60):
    """Allow max_requests per window seconds"""
    now = time.time()

    # Clean old entries
    cutoff = now - window
    request_counts[client_id] = [
        ts for ts in request_counts.get(client_id, [])
        if ts > cutoff
    ]

    # Check limit
    if len(request_counts[client_id]) >= max_requests:
        raise Exception('Rate limit exceeded')

    # Record request
    request_counts[client_id].append(now)

# Use in function
@https_fn.on_request(...)
def handleOAuthCallback(req):
    client_ip = req.headers.get('X-Forwarded-For', req.remote_addr)
    rate_limit(client_ip, max_requests=10, window=60)
    # ... rest of function
```

### Firestore Security Rules

Limit writes to prevent abuse:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      // Users can only read their own profile
      allow read: if request.auth != null && request.auth.uid == userId;

      // Only Cloud Functions can write
      // (verified by checking if request.auth is null - custom token has auth)
      allow write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

## Security Checklist

Before deploying to production:

- [ ] Client secret stored in Secret Manager (not in code)
- [ ] PKCE implemented with crypto-secure random
- [ ] State parameter validated (CSRF protection)
- [ ] JWT signature verified with provider's JWKS
- [ ] JWT claims validated (iss, aud, exp)
- [ ] Only RS256 algorithm accepted for JWTs
- [ ] HTTPS enforced for all endpoints
- [ ] CORS configured with specific origins
- [ ] Input validation on all user inputs
- [ ] Error messages don't leak secrets
- [ ] Secrets not logged
- [ ] Rate limiting implemented
- [ ] Firestore security rules configured
- [ ] Service account has minimal permissions
- [ ] Code reviewed for security issues
- [ ] Dependencies up to date (no known vulnerabilities)

## Security Monitoring

### Cloud Logging

Monitor for suspicious activity:

```bash
# Failed authentication attempts
gcloud logging read "jsonPayload.message:'Token verification failed'" --limit=100

# Rate limit violations
gcloud logging read "jsonPayload.message:'Rate limit exceeded'" --limit=100

# Unauthorized access attempts
gcloud logging read "severity=ERROR AND resource.type=cloud_function" --limit=100
```

### Alerts

Set up alerts for security events:
- Multiple failed token verifications from same IP
- Excessive Cloud Function errors
- Unauthorized Firestore access attempts
- Secret Manager access from unexpected service accounts

## Incident Response

If a security incident occurs:

1. **Immediately**:
   - Rotate client secret
   - Revoke compromised tokens
   - Review Cloud Function logs

2. **Investigate**:
   - Identify scope of compromise
   - Check Firestore for unauthorized access
   - Review user account activity

3. **Remediate**:
   - Deploy security fix
   - Update dependencies
   - Strengthen security rules

4. **Post-Incident**:
   - Document lessons learned
   - Update security checklist
   - Improve monitoring

## References

- [RFC 7636: PKCE](https://datatracker.ietf.org/doc/html/rfc7636)
- [RFC 6749: OAuth 2.0](https://datatracker.ietf.org/doc/html/rfc6749)
- [RFC 8725: JWT Best Practices](https://datatracker.ietf.org/doc/html/rfc8725)
- [OWASP OAuth Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/OAuth_Cheat_Sheet.html)
- [Google Cloud Security Best Practices](https://cloud.google.com/security/best-practices)
