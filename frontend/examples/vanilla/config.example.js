/**
 * Vanilla JS Example Configuration
 *
 * Copy this file to config.js and fill in your credentials.
 * DO NOT commit config.js to version control!
 */

export const firebaseConfig = {
  apiKey: "your-api-key",
  authDomain: "your-project.firebaseapp.com",
  projectId: "your-project-id",
  storageBucket: "your-project.appspot.com",
  messagingSenderId: "123456789",
  appId: "1:123456789:web:abcdef"
};

export const oauthConfig = {
  issuerUrl: 'https://idp.your-provider.com',
  clientId: 'your-client-id',
  redirectUri: window.location.origin + '/index.html',
  scopes: ['openid', 'profile', 'email'],
  cloudFunctionUrl: 'https://your-region-your-project.cloudfunctions.net/handleOAuthCallback'
};
