# Vanilla JavaScript Example

Pure JavaScript implementation of Firebase Manual OAuth with PKCE.

## Setup

1. **Copy configuration file**:
   ```bash
   cp config.example.js config.js
   ```

2. **Update `config.js`** with your credentials:
   - Firebase config (get with: `firebase apps:sdkconfig web`)
   - OAuth provider settings
   - Cloud Function URL

3. **Serve the example**:
   ```bash
   npx http-server -p 8080
   ```

4. **Open in browser**:
   ```
   http://localhost:8080/index.html
   ```

## How It Works

1. User clicks "Sign In with OAuth Provider"
2. `signInWithOAuth()` generates PKCE and redirects to OAuth provider
3. User authenticates with OAuth provider
4. Provider redirects back to this page with authorization code
5. `handleOAuthCallback()` sends code + verifier to Cloud Function
6. Cloud Function returns Firebase custom token
7. Frontend signs in to Firebase with custom token
8. User is authenticated! ✅

## Files

- `index.html` - Single-page application with login/logout UI
- `config.js` - Your configuration (not committed)
- `config.example.js` - Configuration template

## Dependencies

Uses Firebase SDK from CDN (no build step required):
- `firebase/app` - Firebase core
- `firebase/auth` - Firebase Authentication

OAuth handler is imported from `../../auth/oauth-handler.js` (shared module).

## Testing

**Local Testing** (limited):
```bash
npx http-server -p 8080
```

Open http://localhost:8080/index.html

**Note**: OAuth callback will fail locally because redirect URI points to Cloud Function. For full testing, deploy to Firebase Hosting:

```bash
# From repository root
firebase deploy --only hosting
```

## Customization

### Change OAuth Provider

Update `config.js`:
```javascript
export const oauthConfig = {
  issuerUrl: 'https://idp.another-provider.com',
  clientId: 'new-client-id',
  scopes: ['openid', 'profile', 'custom_scope'],
  // ...
};
```

### Add Custom Claims

Custom claims are automatically included in Firebase tokens. Access them:

```javascript
import { getAuth } from 'firebase/auth';

const auth = getAuth();
const user = auth.currentUser;

// Get ID token with claims
const idTokenResult = await user.getIdTokenResult();
console.log('Custom claims:', idTokenResult.claims);

// Access specific claim
const nationalId = idTokenResult.claims.national_id;
```

### Customize UI

Edit `index.html` `<style>` section to match your branding.

## Troubleshooting

**Error: "OAuth handler not initialized"**
- Make sure `initOAuthHandler(oauthConfig)` is called before `signInWithOAuth()`

**Error: "Missing code or state parameter"**
- Check OAuth provider redirect URI is correct
- Make sure callback is handled on same domain as initiated

**Error: "Invalid state parameter"**
- Session may have expired
- Try clearing sessionStorage and logging in again

See [../../docs/TROUBLESHOOTING.md](../../docs/TROUBLESHOOTING.md) for more help.
