# Troubleshooting Guide

Common issues and solutions for Firebase Manual OAuth with PKCE.

## Organization Policy Blocking Public Access

### Error

```
One or more users named in the policy do not belong to a permitted customer,
perhaps due to an organization policy
```

### Cause

Your Google Cloud organization has a policy that restricts who can access Cloud Run services.

### Solution

**Option 1: Modify Organization Policy (Requires Org Admin)**

```bash
# Grant yourself org policy admin role
gcloud organizations add-iam-policy-binding YOUR_ORG_ID \
  --member=user:your-email@example.com \
  --role=roles/orgpolicy.policyAdmin

# Create policy file
cat > allow-public-policy.yaml <<EOF
constraint: constraints/iam.allowedPolicyMemberDomains
listPolicy:
  allowedValues:
    - is:YOUR_DOMAIN.com
  allValues: ALLOW
EOF

# Apply policy
gcloud resource-manager org-policies set-policy allow-public-policy.yaml \
  --project=your-project-id
```

**Option 2: Use IAM Policy File**

```bash
# Create policy file
cat > /tmp/run-policy.json <<EOF
{
  "bindings": [
    {
      "role": "roles/run.invoker",
      "members": ["allUsers"]
    }
  ]
}
EOF

# Apply policy
gcloud run services set-iam-policy handleOAuthCallback \
  /tmp/run-policy.json \
  --region=your-region \
  --project=your-project-id \
  --quiet
```

## Invalid Redirect URI

### Error

OAuth provider shows "Invalid URIs" in red

### Causes

1. Wrong domain (e.g., `.web.app` instead of `.firebaseapp.com`)
2. Missing HTTPS
3. Redirect URI doesn't match exactly

### Solutions

**Check Cloud Function URL**:
```bash
gcloud functions describe handleOAuthCallback \
  --region=your-region \
  --project=your-project-id \
  --format="value(serviceConfig.uri)"
```

**Common Mistakes**:
```
❌ http://... (must be HTTPS)
❌ https://your-project.web.app/callback
❌ https://your-project.firebaseapp.com/callback/ (trailing slash)

✅ https://your-region-your-project.cloudfunctions.net/handleOAuthCallback
```

**Update OAuth Provider**:
- Log in to OAuth provider dashboard
- Find redirect URI configuration
- Copy exact Cloud Function URL (no trailing slash)
- Save and verify it shows green/valid

## 401 Unauthorized from Token Exchange

### Error

```
401 Client Error: Unauthorized for url: https://idp.provider.com/oidc/token
```

### Causes

1. Wrong client secret
2. Client secret not updated in Secret Manager
3. Wrong client ID
4. PKCE verifier mismatch

### Solutions

**Verify Client Secret**:
```bash
# Check current secret
gcloud secrets versions access latest --secret=oauth-client-secret --project=your-project-id

# Update secret
echo -n "NEW_CLIENT_SECRET" | gcloud secrets versions add oauth-client-secret \
  --data-file=- \
  --project=your-project-id
```

**Check Cloud Function Logs**:
```bash
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=handleOAuthCallback" \
  --project=your-project-id \
  --limit=10 \
  --format=json
```

Look for the actual error response from OAuth provider.

**Verify Configuration**:
```bash
# Check environment variables
gcloud functions describe handleOAuthCallback \
  --region=your-region \
  --project=your-project-id \
  --format="value(serviceConfig.environmentVariables)"
```

## Firestore Permission Denied

### Error

```
403 Missing or insufficient permissions
```

### Cause

Cloud Function service account doesn't have Firestore access.

### Solution

```bash
PROJECT_NUMBER=$(gcloud projects describe your-project-id --format="value(projectNumber)")
SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# Grant Firestore access
gcloud projects add-iam-policy-binding your-project-id \
  --member=serviceAccount:${SERVICE_ACCOUNT} \
  --role=roles/datastore.user

# Grant Firebase Admin access
gcloud projects add-iam-policy-binding your-project-id \
  --member=serviceAccount:${SERVICE_ACCOUNT} \
  --role=roles/firebase.admin
```

Redeploy function:
```bash
firebase deploy --only functions:handleOAuthCallback --project=your-project-id
```

## Custom Token Creation Error

### Error

```
Permission 'iam.serviceAccounts.signBlob' denied
```

### Cause

Cloud Function service account can't sign tokens.

### Solution

```bash
PROJECT_NUMBER=$(gcloud projects describe your-project-id --format="value(projectNumber)")
SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# Grant token creator role
gcloud projects add-iam-policy-binding your-project-id \
  --member=serviceAccount:${SERVICE_ACCOUNT} \
  --role=roles/iam.serviceAccountTokenCreator

# Also grant to itself
gcloud iam service-accounts add-iam-policy-binding ${SERVICE_ACCOUNT} \
  --member=serviceAccount:${SERVICE_ACCOUNT} \
  --role=roles/iam.serviceAccountTokenCreator \
  --project=your-project-id
```

## Python SDK Syntax Error

### Error

```
create_custom_token() got an unexpected keyword argument 'additional_claims'
```

### Cause

Python Firebase Admin SDK uses `developer_claims`, not `additional_claims`.

### Solution

Update `main.py`:

```python
# ❌ Wrong (JavaScript SDK syntax)
custom_token = auth.create_custom_token(
    uid,
    additional_claims={'custom': 'value'}
)

# ✅ Correct (Python SDK syntax)
custom_token = auth.create_custom_token(
    uid,
    developer_claims={'custom': 'value'}
)
```

## Invalid Firebase API Key

### Error

```
Firebase: Error (auth/api-key-not-valid)
```

### Cause

Frontend using wrong Firebase API key.

### Solution

Get correct Firebase config:
```bash
firebase apps:sdkconfig web --project=your-project-id
```

Update `config.js`:
```javascript
export const firebaseConfig = {
  apiKey: "CORRECT_API_KEY_HERE",
  authDomain: "your-project.firebaseapp.com",
  projectId: "your-project-id",
  storageBucket: "your-project.appspot.com",
  messagingSenderId: "123456789",
  appId: "1:123456789:web:abcdef"
};
```

## State Mismatch Error

### Error

```
Invalid state parameter - possible CSRF attack
```

### Causes

1. User navigating back/forward during OAuth flow
2. Session expired
3. Multiple tabs/windows
4. Browser blocking sessionStorage

### Solutions

**Clear sessionStorage**:
```javascript
sessionStorage.clear();
```

**Restart OAuth flow**:
- Click login button again
- Don't use browser back button during authentication

**Check browser settings**:
- Ensure cookies and sessionStorage are enabled
- Disable strict tracking prevention for your site
- Try in incognito/private mode

## JWT Verification Failed

### Error

```
ID token verification failed: Signature verification failed
```

### Causes

1. Clock skew between servers
2. Wrong JWKS URL
3. Token expired
4. Wrong issuer/audience

### Solutions

**Check token claims**:
```bash
# In Cloud Function logs, look for decoded token
gcloud logging read "resource.type=cloud_function" \
  --project=your-project-id \
  --limit=10 \
  --format=json | jq '.[] | select(.jsonPayload.message | contains("Token verified"))'
```

**Verify JWKS URL**:
```bash
curl https://idp.your-provider.com/.well-known/jwks.json
```

**Check system time**:
```bash
# In Cloud Function (logs)
import datetime
logging.info(f"Server time: {datetime.datetime.utcnow()}")
```

**Update JWT verification**:
```python
# Allow for clock skew
decoded_token = jwt.decode(
    id_token,
    signing_key.key,
    algorithms=['RS256'],
    audience=OAUTH_CLIENT_ID,
    issuer=OAUTH_ISSUER_URL,
    leeway=60  # Allow 60 seconds clock skew
)
```

## CORS Errors

### Error

```
Access to fetch at '...' from origin '...' has been blocked by CORS policy
```

### Cause

Cloud Function not configured for CORS from your domain.

### Solution

Update `main.py`:

```python
@https_fn.on_request(
    cors=options.CorsOptions(
        cors_origins=[
            "https://your-app.com",
            "https://your-project.firebaseapp.com",
            "https://your-project.web.app"
        ],
        cors_methods=["POST", "OPTIONS"]
    ),
    region="your-region"
)
def handleOAuthCallback(req: https_fn.Request) -> https_fn.Response:
    # ...
```

Redeploy:
```bash
firebase deploy --only functions:handleOAuthCallback --project=your-project-id
```

## Local Testing Issues

### Problem

OAuth callback fails when testing locally because redirect URI points to Cloud Function.

### Solution

**Option 1: Use Firebase Hosting Preview Channel**

```bash
# Deploy to preview channel
firebase hosting:channel:deploy preview --project=your-project-id

# Get preview URL
firebase hosting:channel:list --project=your-project-id
```

Update OAuth provider redirect URI to preview URL temporarily.

**Option 2: Use ngrok for Local Testing**

```bash
# Install ngrok
npm install -g ngrok

# Expose local server
ngrok http 8080

# Use ngrok URL as redirect URI
# https://abc123.ngrok.io/callback
```

**Option 3: Cloud Function Emulator**

```bash
# Start Firebase emulators
firebase emulators:start --only functions,hosting

# Use emulator URLs in config
# http://localhost:5001/your-project/your-region/handleOAuthCallback
```

**Note**: Most OAuth providers require HTTPS, so ngrok or preview channels are recommended.

## Debugging Tips

### Enable Verbose Logging

**Cloud Function**:
```python
import logging
logging.basicConfig(level=logging.DEBUG)

# Log request details
logger.debug(f"Request headers: {req.headers}")
logger.debug(f"Request body: {request_json}")
logger.debug(f"Token response: {token_response}")
```

**Frontend**:
```javascript
// Add console.log at each step
console.log('1. Initiating OAuth flow');
console.log('2. PKCE generated:', { challenge });
console.log('3. Redirecting to:', authUrl);
console.log('4. Received callback:', { code, state });
console.log('5. Sending to Cloud Function');
console.log('6. Received custom token');
console.log('7. Signing in to Firebase');
```

### Check Data Flow

Verify each step:

1. **Frontend generates PKCE** → Check sessionStorage
```javascript
console.log('Verifier:', sessionStorage.getItem('pkce_code_verifier'));
```

2. **OAuth provider receives challenge** → Check redirect URL
```javascript
console.log('Authorization URL:', authUrl);
```

3. **Provider returns code** → Check callback URL
```javascript
console.log('Callback params:', window.location.search);
```

4. **Cloud Function receives request** → Check logs
```bash
gcloud logging read "resource.type=cloud_function" --limit=10
```

5. **Token exchange succeeds** → Check logs
```bash
gcloud logging read "jsonPayload.message:'Token verified'" --limit=10
```

6. **Firestore updated** → Check database
```bash
gcloud firestore documents list users --limit=10
```

7. **Custom token created** → Check logs
```bash
gcloud logging read "jsonPayload.message:'Custom token created'" --limit=10
```

8. **Firebase sign-in** → Check frontend
```javascript
import { getAuth } from 'firebase/auth';
const auth = getAuth();
console.log('Current user:', auth.currentUser);
```

### Common Checklist

Before asking for help, verify:

- [ ] Cloud Function deployed successfully
- [ ] Cloud Function publicly accessible (`allUsers` has `run.invoker`)
- [ ] OAuth provider redirect URI matches Cloud Function URL exactly
- [ ] Client secret updated in Secret Manager
- [ ] Service account has all required roles (datastore.user, firebase.admin, iam.serviceAccountTokenCreator)
- [ ] Firestore database created
- [ ] Frontend using correct Firebase config
- [ ] Frontend using correct OAuth config
- [ ] CORS configured correctly
- [ ] No browser errors in console
- [ ] No Cloud Function errors in logs

## Getting Help

If you're still stuck:

1. **Check Cloud Function logs**:
```bash
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=handleOAuthCallback" \
  --project=your-project-id \
  --limit=50 \
  --format=json > logs.json
```

2. **Check browser console** (F12 → Console)

3. **Test OAuth provider directly**:
```bash
# Test JWKS endpoint
curl https://idp.provider.com/.well-known/jwks.json

# Test OpenID configuration
curl https://idp.provider.com/.well-known/openid-configuration
```

4. **Create minimal reproduction**:
- Use `frontend/examples/vanilla/` example
- Update config with your credentials
- Test in clean browser (incognito mode)

5. **Open GitHub issue** with:
- Error message (redact secrets!)
- Cloud Function logs (redact secrets!)
- Browser console output
- Steps to reproduce
- Configuration (redact secrets!)
