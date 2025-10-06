# Deployment Guide

Complete step-by-step guide to deploy the Firebase Manual OAuth with PKCE solution to a new Firebase project.

## Prerequisites

- Google Cloud account
- Firebase CLI installed: `npm install -g firebase-tools`
- Python 3.13+ installed
- Access to OAuth provider (Kenni.is) developer portal

## Step 1: Create and Configure Firebase Project

### 1.1 Create Firebase Project

```bash
# Login to Firebase
firebase login

# Create new GCP project (or use existing)
gcloud projects create YOUR-PROJECT-ID --name="Your Project Name"

# Set active project
gcloud config set project YOUR-PROJECT-ID

# Add Firebase to the project
firebase projects:addfirebase YOUR-PROJECT-ID
```

### 1.2 Enable Billing

**REQUIRED** - Cloud Functions and Secret Manager require billing.

```bash
# List billing accounts
gcloud billing accounts list

# Link billing account to project
gcloud billing projects link YOUR-PROJECT-ID --billing-account=YOUR-BILLING-ACCOUNT-ID
```

**Or via Console:**
Visit: https://console.cloud.google.com/billing/linkedaccount?project=YOUR-PROJECT-ID

### 1.3 Enable Required APIs

```bash
# Enable all required APIs at once
gcloud services enable \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  firestore.googleapis.com \
  identitytoolkit.googleapis.com \
  --project=YOUR-PROJECT-ID
```

### 1.4 Create Firebase Web App

```bash
firebase apps:create WEB "OAuth PKCE Demo" --project=YOUR-PROJECT-ID

# Get the Firebase config
firebase apps:sdkconfig web --project=YOUR-PROJECT-ID
```

Save the config output - you'll need it for `demo.html`.

## Step 2: Configure OAuth Provider (Kenni.is)

### 2.1 Create Application in Kenni.is Developer Portal

1. Go to Kenni.is developer portal: https://developers.kenni.is
2. Click "Create a new application"
3. Fill in details:
   - **Name**: Your app name (e.g., "Firebase OAuth PKCE Demo")
   - **Application type**: Web (SPA)
   - **Application URI**: `https://YOUR-PROJECT-ID.web.app`
   - **Client ID**: Will be auto-generated (e.g., `@your-org/your-app-name`)
   - **Redirect URIs** (add both):
     ```
     https://YOUR-REGION-YOUR-PROJECT-ID.cloudfunctions.net/handleOAuthCallback
     https://YOUR-PROJECT-ID.web.app/demo.html
     ```
   - **PKCE**: Required (enabled)

4. Save and note your **Client Secret**

## Step 3: Set Up Project Files

### 3.1 Clone or Copy Repository

```bash
git clone https://github.com/gudrodur/firebase-manual-oauth-pkce.git
cd firebase-manual-oauth-pkce
```

### 3.2 Configure Environment Variables

Edit `functions/.env`:

```env
# OAuth Provider Configuration
OAUTH_ISSUER_URL=https://idp.kenni.is/YOUR-ORG
OAUTH_CLIENT_ID=@your-org/your-app-name
OAUTH_REDIRECT_URI=https://YOUR-REGION-YOUR-PROJECT-ID.cloudfunctions.net/handleOAuthCallback
OAUTH_CLIENT_SECRET=your-client-secret-from-kenni

# Custom Claim Configuration
CUSTOM_CLAIM_NAME=kennitala
```

**IMPORTANT**: The `.env` file is gitignored for security. Never commit secrets!

### 3.3 Update Firebase Configuration in Demo Page

Edit `public/demo.html` with your Firebase config:

```javascript
const firebaseConfig = {
  apiKey: "YOUR-API-KEY",
  authDomain: "YOUR-PROJECT-ID.firebaseapp.com",
  projectId: "YOUR-PROJECT-ID",
  storageBucket: "YOUR-PROJECT-ID.firebasestorage.app",
  messagingSenderId: "YOUR-SENDER-ID",
  appId: "YOUR-APP-ID"
};

const oauthConfig = {
  issuerUrl: 'https://idp.kenni.is/YOUR-ORG',
  clientId: '@your-org/your-app-name',
  redirectUri: window.location.origin + '/demo.html',
  scopes: ['openid', 'profile', 'email', 'phone_number', 'national_id'],
  cloudFunctionUrl: 'https://YOUR-REGION-YOUR-PROJECT-ID.cloudfunctions.net/handleOAuthCallback'
};
```

## Step 4: Create Firestore Database

```bash
# Create Firestore database in your preferred region
gcloud firestore databases create --location=YOUR-REGION --project=YOUR-PROJECT-ID
```

**Common regions:**
- `europe-west2` (London)
- `us-central1` (Iowa)
- `asia-northeast1` (Tokyo)

## Step 5: Configure IAM Permissions

### 5.1 Grant Service Account Permissions

The Cloud Function needs permission to create custom tokens:

```bash
# Get the service account email used by Cloud Functions
SERVICE_ACCOUNT=$(gcloud functions describe handleOAuthCallback \
  --region=YOUR-REGION \
  --project=YOUR-PROJECT-ID \
  --gen2 \
  --format="value(serviceConfig.serviceAccountEmail)")

# If function doesn't exist yet, use compute service account:
SERVICE_ACCOUNT="$(gcloud projects describe YOUR-PROJECT-ID --format='value(projectNumber)')-compute@developer.gserviceaccount.com"

# Grant Token Creator role
gcloud projects add-iam-policy-binding YOUR-PROJECT-ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/iam.serviceAccountTokenCreator"
```

## Step 6: Enable Firebase Authentication

**Via Firebase Console** (easiest):
1. Go to: https://console.firebase.google.com/project/YOUR-PROJECT-ID/authentication/users
2. Click "Get started"
3. Done!

**Via gcloud** (if you prefer):
```bash
# Initialize Firebase Authentication
firebase init auth --project=YOUR-PROJECT-ID
```

## Step 7: Store Client Secret in Secret Manager

```bash
# Create secret
echo -n "YOUR-CLIENT-SECRET" | gcloud secrets create oauth-client-secret \
  --data-file=- \
  --project=YOUR-PROJECT-ID

# Verify
gcloud secrets versions access latest --secret=oauth-client-secret --project=YOUR-PROJECT-ID
```

## Step 8: Deploy Cloud Function

```bash
cd functions

# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Deploy
firebase deploy --only functions:handleOAuthCallback --project=YOUR-PROJECT-ID
```

**Expected output:**
```
✔  functions[handleOAuthCallback(YOUR-REGION)] Successful update operation.
Function URL (handleOAuthCallback): https://YOUR-REGION-YOUR-PROJECT-ID.cloudfunctions.net/handleOAuthCallback
```

**Note the Function URL** - you need to add it to Kenni.is Redirect URIs if not done already.

## Step 9: Deploy Frontend (Firebase Hosting)

```bash
cd ..  # Back to project root

# Deploy hosting
firebase deploy --only hosting --project=YOUR-PROJECT-ID
```

**Expected output:**
```
✔  Deploy complete!
Hosting URL: https://YOUR-PROJECT-ID.web.app
```

## Step 10: Test the OAuth Flow

1. Visit: `https://YOUR-PROJECT-ID.web.app/demo.html`
2. Click "🇮🇸 Sign In with Kenni.is"
3. Authenticate with Kenni.is
4. You should see:
   - ✅ Successfully Authenticated!
   - Name, Email, Phone Number
   - Kennitala (Icelandic National ID)
   - Firebase UID

## Troubleshooting

### Common Issues

#### 1. "Missing required environment variables"

**Cause**: `.env` file not loaded or variables not set

**Fix**:
```bash
# Check Cloud Function env vars
gcloud functions describe handleOAuthCallback \
  --region=YOUR-REGION \
  --project=YOUR-PROJECT-ID \
  --gen2 \
  --format="yaml(serviceConfig.environmentVariables)"
```

All required variables should be present:
- `OAUTH_ISSUER_URL`
- `OAUTH_CLIENT_ID`
- `OAUTH_CLIENT_SECRET`
- `OAUTH_REDIRECT_URI`
- `CUSTOM_CLAIM_NAME`

#### 2. "400 Bad Request" during token exchange

**Cause**: Redirect URI mismatch

**Fix**:
- Ensure redirect URIs in Kenni.is **exactly match** what's being sent
- Check both:
  - Cloud Function URL: `https://YOUR-REGION-YOUR-PROJECT-ID.cloudfunctions.net/handleOAuthCallback`
  - Demo page URL: `https://YOUR-PROJECT-ID.web.app/demo.html`

#### 3. "404 Not Found" when fetching JWKS

**Cause**: Incorrect JWKS URL

**Fix**: Ensure `main.py` uses:
```python
jwks_url = f"{OAUTH_ISSUER_URL}/oidc/jwks"
```

Not:
```python
jwks_url = f"{OAUTH_ISSUER_URL}/.well-known/jwks.json"  # ❌ Wrong for Kenni.is
```

#### 4. "Permission denied: iam.serviceAccounts.signBlob"

**Cause**: Service account lacks permission to create custom tokens

**Fix**: See Step 5.1 above to grant `roles/iam.serviceAccountTokenCreator`

#### 5. "auth/configuration-not-found"

**Cause**: Firebase Authentication not enabled

**Fix**: See Step 6 above to enable Firebase Authentication

#### 6. Missing user data (name, email, kennitala)

**Cause**: Not requesting required scopes

**Fix**: Ensure demo.html includes all scopes:
```javascript
scopes: ['openid', 'profile', 'email', 'phone_number', 'national_id']
```

### Checking Logs

```bash
# Cloud Function logs
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=handleOAuthCallback" \
  --project=YOUR-PROJECT-ID \
  --limit=50 \
  --format="table(timestamp, severity, textPayload)"

# Cloud Run logs (more detailed)
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=handleoauthcallback" \
  --project=YOUR-PROJECT-ID \
  --limit=50 \
  --freshness=10m
```

## Cost Estimates

### Free Tier Limits (as of 2025)

- **Cloud Functions**: 2M invocations/month free
- **Firestore**: 1 GiB storage, 50K reads, 20K writes per day free
- **Firebase Hosting**: 10 GB storage, 360 MB/day transfer free
- **Secret Manager**: 6 active secret versions free

### Expected Costs for Demo

For a demo with low traffic (<1000 authentications/month):
- **Estimated cost**: $0/month (within free tier)

For production with moderate traffic:
- Cloud Functions: ~$0.40 per 1M invocations
- Firestore: ~$0.06 per 100K reads
- Total: <$5/month for most small-to-medium apps

## Security Checklist

- [ ] Client secret stored in Secret Manager (not in code)
- [ ] `.env` file in `.gitignore`
- [ ] Redirect URIs allowlist configured in Kenni.is
- [ ] HTTPS enforced (Firebase Hosting does this by default)
- [ ] PKCE enabled and required
- [ ] State parameter validated (oauth-handler.js does this)
- [ ] Service account has minimal required permissions
- [ ] Firestore security rules configured (if using Firestore for data)

## Next Steps

After successful deployment:

1. **Configure Firestore Security Rules** (if storing user data)
2. **Set up monitoring** with Cloud Monitoring
3. **Configure custom domain** for Firebase Hosting
4. **Add error tracking** (e.g., Sentry)
5. **Implement token refresh** for long-lived sessions
6. **Add logout endpoint** to revoke tokens

## Support

For issues specific to:
- **Kenni.is OAuth**: Contact Kenni.is support
- **Firebase**: https://firebase.google.com/support
- **This repository**: Create an issue on GitHub

## Reference Links

- [Kenni.is Developer Portal](https://developers.kenni.is)
- [Firebase Documentation](https://firebase.google.com/docs)
- [OAuth 2.0 with PKCE](https://oauth.net/2/pkce/)
- [Firebase Custom Tokens](https://firebase.google.com/docs/auth/admin/create-custom-tokens)
