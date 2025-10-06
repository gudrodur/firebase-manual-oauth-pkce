/**
 * OAuth Configuration Example
 *
 * Copy this file to config.js and fill in your OAuth provider details.
 * DO NOT commit config.js to version control - add it to .gitignore
 */

export const oauthConfig = {
  // OAuth Provider Settings
  issuerUrl: 'https://idp.your-provider.com',
  clientId: 'your-client-id',
  redirectUri: 'https://your-app.com/callback',
  scopes: ['openid', 'profile', 'email'],

  // Cloud Function URL
  cloudFunctionUrl: 'https://your-region-your-project.cloudfunctions.net/handleOAuthCallback'
};

// Firebase Configuration
export const firebaseConfig = {
  apiKey: "your-api-key",
  authDomain: "your-project.firebaseapp.com",
  projectId: "your-project",
  storageBucket: "your-project.appspot.com",
  messagingSenderId: "123456789",
  appId: "1:123456789:web:abcdef"
};
