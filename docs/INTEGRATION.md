# Integration Guide

Complete step-by-step guide to integrate Firebase Manual OAuth with PKCE into your project.

## Prerequisites

- Firebase project with Identity Platform enabled
- Google Cloud project (same as Firebase project)
- OAuth provider that supports PKCE
- Node.js 18+ installed locally
- Firebase CLI installed: `npm install -g firebase-tools`

## Step 1: Firebase Setup

### 1.1 Create Firebase Project

If you don't have a Firebase project:

```bash
# Login to Firebase
firebase login

# Create new project
firebase projects:create your-project-id
```

### 1.2 Enable Identity Platform

```bash
# Enable Firebase Authentication
gcloud services enable identitytoolkit.googleapis.com --project=your-project-id

# Enable Firestore (for user profiles)
gcloud services enable firestore.googleapis.com --project=your-project-id
gcloud firestore databases create --location=your-region --project=your-project-id
```

### 1.3 Enable Cloud Functions

```bash
gcloud services enable cloudfunctions.googleapis.com --project=your-project-id
gcloud services enable cloudbuild.googleapis.com --project=your-project-id
```

## Step 2: Configure OAuth Provider

### 2.1 Register Your Application

Register your application with your OAuth provider (e.g., Kenni.is, Auth0, Okta).

You'll need to configure:
- **Application Name**: Your app name
- **Application URI**: `https://your-app.com`
- **Redirect URI**: Will be set after deploying Cloud Function (Step 3)

### 2.2 Note Your Credentials

Save these values - you'll need them later:
- Client ID
- Client Secret
- Issuer URL
- Authorization endpoint
- Token endpoint

## Step 3: Deploy Cloud Function

### 3.1 Configure Environment Variables

Create `.env` file in `functions/` directory:

```bash
cd functions
cp .env.example .env
```

Edit `.env`:

```env
OAUTH_ISSUER_URL=https://idp.your-provider.com
OAUTH_CLIENT_ID=your-client-id
OAUTH_CLIENT_SECRET=your-client-secret
OAUTH_REDIRECT_URI=https://your-region-your-project.cloudfunctions.net/handleOAuthCallback
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_STORAGE_BUCKET=your-project.appspot.com
CUSTOM_CLAIM_NAME=national_id  # Optional: your custom claim name
```

### 3.2 Store Client Secret in Secret Manager

**IMPORTANT**: Never commit client secrets to version control!

```bash
# Create secret in Secret Manager
echo -n "your-client-secret" | gcloud secrets create oauth-client-secret \
  --data-file=- \
  --project=your-project-id

# Grant Cloud Functions access to secret
PROJECT_NUMBER=$(gcloud projects describe your-project-id --format="value(projectNumber)")
gcloud secrets add-iam-policy-binding oauth-client-secret \
  --member=serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com \
  --role=roles/secretmanager.secretAccessor \
  --project=your-project-id
```

### 3.3 Update Cloud Function to Use Secret

Modify `main.py` to load secret from Secret Manager:

```python
from google.cloud import secretmanager

def access_secret_version(secret_id: str) -> str:
    client = secretmanager.SecretManagerServiceClient()
    project_id = os.environ.get('FIREBASE_PROJECT_ID')
    name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode('UTF-8')

# Load client secret from Secret Manager
OAUTH_CLIENT_SECRET = access_secret_version('oauth-client-secret')
```

### 3.4 Deploy Cloud Function

```bash
# Initialize Firebase (if not already done)
firebase init functions

# Deploy function
firebase deploy --only functions:handleOAuthCallback --project=your-project-id
```

Note the deployed function URL:
```
https://your-region-your-project.cloudfunctions.net/handleOAuthCallback
```

### 3.5 Configure Function IAM Permissions

Grant necessary permissions to the Cloud Function service account:

```bash
PROJECT_NUMBER=$(gcloud projects describe your-project-id --format="value(projectNumber)")
SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# Firestore access
gcloud projects add-iam-policy-binding your-project-id \
  --member=serviceAccount:${SERVICE_ACCOUNT} \
  --role=roles/datastore.user

# Firebase Admin access
gcloud projects add-iam-policy-binding your-project-id \
  --member=serviceAccount:${SERVICE_ACCOUNT} \
  --role=roles/firebase.admin

# Custom token creation
gcloud projects add-iam-policy-binding your-project-id \
  --member=serviceAccount:${SERVICE_ACCOUNT} \
  --role=roles/iam.serviceAccountTokenCreator
```

### 3.6 Make Function Publicly Accessible

```bash
gcloud functions add-invoker-policy-binding handleOAuthCallback \
  --region=your-region \
  --member=allUsers \
  --project=your-project-id
```

If you get an organization policy error, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md#organization-policy-blocking-public-access).

## Step 4: Update OAuth Provider Redirect URI

Return to your OAuth provider configuration and set the redirect URI to your Cloud Function URL:

```
https://your-region-your-project.cloudfunctions.net/handleOAuthCallback
```

## Step 5: Integrate Frontend

### 5.1 Install Dependencies

```bash
npm install firebase
```

### 5.2 Configure OAuth Handler

Create `config.js` (copy from `config.example.js`):

```javascript
export const oauthConfig = {
  issuerUrl: 'https://idp.your-provider.com',
  clientId: 'your-client-id',
  redirectUri: 'https://your-region-your-project.cloudfunctions.net/handleOAuthCallback',
  scopes: ['openid', 'profile', 'email'],
  cloudFunctionUrl: 'https://your-region-your-project.cloudfunctions.net/handleOAuthCallback'
};

export const firebaseConfig = {
  apiKey: "your-api-key",
  authDomain: "your-project.firebaseapp.com",
  projectId: "your-project-id",
  storageBucket: "your-project.appspot.com",
  messagingSenderId: "123456789",
  appId: "1:123456789:web:abcdef"
};
```

Get Firebase config:
```bash
firebase apps:sdkconfig web --project=your-project-id
```

### 5.3 Initialize OAuth Handler

In your app's entry point:

```javascript
import { initializeApp } from 'firebase/app';
import { initOAuthHandler } from './auth/oauth-handler.js';
import { firebaseConfig, oauthConfig } from './config.js';

// Initialize Firebase
const app = initializeApp(firebaseConfig);

// Initialize OAuth handler
initOAuthHandler(oauthConfig);
```

### 5.4 Add Login Button

```javascript
import { signInWithOAuth } from './auth/oauth-handler.js';

document.getElementById('login-btn').addEventListener('click', async () => {
  try {
    await signInWithOAuth({
      returnUrl: '/dashboard'  // Optional: where to redirect after login
    });
  } catch (error) {
    console.error('Login failed:', error);
  }
});
```

### 5.5 Handle OAuth Callback

Create a callback page (e.g., `/callback.html`):

```html
<!DOCTYPE html>
<html>
<head>
  <title>Authenticating...</title>
</head>
<body>
  <p>Completing authentication...</p>
  <script type="module">
    import { handleOAuthCallback } from './auth/oauth-handler.js';

    try {
      const { user, returnUrl } = await handleOAuthCallback();
      console.log('Authenticated user:', user);

      // Redirect to return URL or default page
      window.location.href = returnUrl || '/';

    } catch (error) {
      console.error('Authentication failed:', error);
      window.location.href = '/?error=auth_failed';
    }
  </script>
</body>
</html>
```

## Step 6: Test the Integration

### 6.1 Test Locally (Frontend Only)

```bash
# Serve your frontend
npx http-server -p 8080
```

**Note**: OAuth callback will fail locally because the redirect URI points to your Cloud Function. For full local testing, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md#local-testing).

### 6.2 Test in Production

Deploy your frontend to Firebase Hosting:

```bash
firebase deploy --only hosting --project=your-project-id
```

Test the complete flow:
1. Click login button
2. Authenticate with OAuth provider
3. Get redirected back to your app
4. User should be signed in to Firebase

### 6.3 Verify User Profile

Check Firestore for user profile:

```bash
gcloud firestore documents list users --project=your-project-id
```

## Step 7: Monitor and Debug

### 7.1 View Cloud Function Logs

```bash
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=handleOAuthCallback" \
  --project=your-project-id \
  --limit=50 \
  --format=json
```

### 7.2 Enable Debug Logging

Add to `functions/main.py`:

```python
logging.basicConfig(level=logging.DEBUG)
```

Redeploy:
```bash
firebase deploy --only functions:handleOAuthCallback --project=your-project-id
```

## Common Issues

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for solutions to common problems:

- Organization policy blocking public access
- Invalid redirect URI
- 401 Unauthorized errors
- Missing permissions
- Token verification failures

## Next Steps

- [Architecture Overview](ARCHITECTURE.md) - Understand how it works
- [Security Best Practices](SECURITY.md) - Secure your implementation
- [Examples](../frontend/examples/) - Framework-specific examples

## Support

For issues and questions:
- Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- Review Cloud Function logs
- Check OAuth provider documentation
- Open an issue on GitHub
