/**
 * Firebase Manual OAuth with PKCE - Frontend Module
 *
 * This module handles the OAuth flow with PKCE on the client side:
 * 1. Generate PKCE parameters (code_verifier and code_challenge)
 * 2. Redirect to OAuth provider for authentication
 * 3. Handle callback with authorization code
 * 4. Send code and verifier to Cloud Function
 * 5. Receive custom token and sign in to Firebase
 *
 * Usage:
 *   import { initOAuthHandler, signInWithOAuth } from './oauth-handler.js';
 *
 *   // Initialize (configure OAuth provider settings)
 *   initOAuthHandler({
 *     issuerUrl: 'https://idp.provider.com',
 *     clientId: 'your-client-id',
 *     redirectUri: 'https://your-app.com/callback',
 *     scopes: ['openid', 'profile', 'email'],
 *     cloudFunctionUrl: 'https://your-region-your-project.cloudfunctions.net/handleOAuthCallback'
 *   });
 *
 *   // Initiate OAuth flow
 *   await signInWithOAuth();
 *
 *   // Handle callback (call this on your callback page)
 *   await handleOAuthCallback();
 */

import { getAuth, signInWithCustomToken } from 'firebase/auth';

// Configuration storage
let oauthConfig = null;

/**
 * Initialize OAuth handler with provider configuration
 *
 * @param {Object} config - OAuth configuration
 * @param {string} config.issuerUrl - OAuth provider's issuer URL
 * @param {string} config.clientId - OAuth client ID
 * @param {string} config.redirectUri - OAuth redirect URI (your callback page)
 * @param {string[]} config.scopes - OAuth scopes to request
 * @param {string} config.cloudFunctionUrl - Your Cloud Function URL
 */
export function initOAuthHandler(config) {
  if (!config.issuerUrl || !config.clientId || !config.redirectUri || !config.cloudFunctionUrl) {
    throw new Error('Missing required OAuth configuration');
  }

  oauthConfig = {
    issuerUrl: config.issuerUrl,
    clientId: config.clientId,
    redirectUri: config.redirectUri,
    scopes: config.scopes || ['openid', 'profile', 'email'],
    cloudFunctionUrl: config.cloudFunctionUrl
  };
}

/**
 * Generate cryptographically secure random string for PKCE
 * @returns {string} Base64URL-encoded random string
 */
function generateRandomString() {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return base64URLEncode(array);
}

/**
 * Base64URL encode (RFC 4648)
 * @param {Uint8Array} buffer - Data to encode
 * @returns {string} Base64URL-encoded string
 */
function base64URLEncode(buffer) {
  const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');
}

/**
 * SHA-256 hash function
 * @param {Uint8Array} data - Data to hash
 * @returns {Promise<ArrayBuffer>} SHA-256 hash
 */
async function sha256(data) {
  return crypto.subtle.digest('SHA-256', data);
}

/**
 * Generate PKCE code_verifier and code_challenge
 * @returns {Promise<{verifier: string, challenge: string}>}
 */
async function generatePKCE() {
  // Generate code_verifier (random string)
  const verifier = generateRandomString();

  // Generate code_challenge (SHA-256 hash of verifier)
  const encoder = new TextEncoder();
  const data = encoder.encode(verifier);
  const hash = await sha256(data);
  const challenge = base64URLEncode(new Uint8Array(hash));

  return { verifier, challenge };
}

/**
 * Initiate OAuth flow with PKCE
 * Redirects user to OAuth provider for authentication
 *
 * @param {Object} options - Optional parameters
 * @param {string} options.state - Custom state parameter (default: random)
 * @param {string} options.returnUrl - URL to return to after authentication
 */
export async function signInWithOAuth(options = {}) {
  if (!oauthConfig) {
    throw new Error('OAuth handler not initialized. Call initOAuthHandler() first.');
  }

  // Generate PKCE parameters
  const { verifier, challenge } = await generatePKCE();
  const state = options.state || generateRandomString();

  // Store PKCE verifier and state in sessionStorage
  sessionStorage.setItem('pkce_code_verifier', verifier);
  sessionStorage.setItem('oauth_state', state);

  // Store return URL if provided
  if (options.returnUrl) {
    sessionStorage.setItem('return_url', options.returnUrl);
  }

  // Build authorization URL
  const params = new URLSearchParams({
    client_id: oauthConfig.clientId,
    redirect_uri: oauthConfig.redirectUri,
    response_type: 'code',
    scope: oauthConfig.scopes.join(' '),
    code_challenge: challenge,
    code_challenge_method: 'S256',
    state: state
  });

  const authUrl = `${oauthConfig.issuerUrl}/oidc/auth?${params.toString()}`;

  // Redirect to OAuth provider
  window.location.assign(authUrl);
}

/**
 * Handle OAuth callback
 * Processes authorization code and completes Firebase sign-in
 *
 * Call this function on your callback page to complete the OAuth flow.
 *
 * @returns {Promise<{user: Object, returnUrl: string|null}>}
 * @throws {Error} If callback handling fails
 */
export async function handleOAuthCallback() {
  if (!oauthConfig) {
    throw new Error('OAuth handler not initialized. Call initOAuthHandler() first.');
  }

  // Parse URL parameters
  const params = new URLSearchParams(window.location.search);
  const code = params.get('code');
  const state = params.get('state');
  const error = params.get('error');

  // Handle OAuth errors
  if (error) {
    const errorDescription = params.get('error_description') || 'Authentication failed';
    throw new Error(`OAuth Error: ${error} - ${errorDescription}`);
  }

  // Validate required parameters
  if (!code || !state) {
    throw new Error('Missing authorization code or state parameter');
  }

  // Retrieve stored values from sessionStorage
  const storedVerifier = sessionStorage.getItem('pkce_code_verifier');
  const storedState = sessionStorage.getItem('oauth_state');
  const returnUrl = sessionStorage.getItem('return_url');

  // Validate state (CSRF protection)
  if (state !== storedState) {
    throw new Error('Invalid state parameter - possible CSRF attack');
  }

  if (!storedVerifier) {
    throw new Error('Missing PKCE verifier - session may have expired');
  }

  try {
    // Exchange authorization code for custom token via Cloud Function
    const response = await fetch(oauthConfig.cloudFunctionUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        code: code,
        codeVerifier: storedVerifier
      })
    });

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}));
      throw new Error(errorData.message || `Cloud Function error: ${response.status}`);
    }

    const data = await response.json();
    const { customToken, uid } = data;

    if (!customToken) {
      throw new Error('No custom token received from Cloud Function');
    }

    // Sign in to Firebase with custom token
    const auth = getAuth();
    const userCredential = await signInWithCustomToken(auth, customToken);

    // Clean up sessionStorage
    sessionStorage.removeItem('pkce_code_verifier');
    sessionStorage.removeItem('oauth_state');
    sessionStorage.removeItem('return_url');

    console.log('✅ Successfully authenticated:', userCredential.user);

    return {
      user: userCredential.user,
      returnUrl: returnUrl
    };

  } catch (error) {
    // Clean up sessionStorage on error
    sessionStorage.removeItem('pkce_code_verifier');
    sessionStorage.removeItem('oauth_state');
    sessionStorage.removeItem('return_url');

    console.error('❌ OAuth callback error:', error);
    throw error;
  }
}

/**
 * Check if current page is OAuth callback
 * @returns {boolean} True if URL contains OAuth callback parameters
 */
export function isOAuthCallback() {
  const params = new URLSearchParams(window.location.search);
  return params.has('code') || params.has('error');
}
