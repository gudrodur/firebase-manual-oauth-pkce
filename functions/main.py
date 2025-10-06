"""
Firebase Manual OAuth with PKCE - Cloud Function

This Cloud Function handles OAuth token exchange for providers requiring PKCE,
then creates Firebase custom tokens for authentication.

Flow:
1. Receive authorization code and PKCE verifier from frontend
2. Exchange code for tokens with OAuth provider (using PKCE verifier)
3. Verify ID token from OAuth provider
4. Create or update user profile in Firestore
5. Generate Firebase custom token with custom claims
6. Return custom token to frontend for sign-in

Environment Variables Required:
- OAUTH_ISSUER_URL: OAuth provider's issuer URL (e.g., https://idp.provider.com)
- OAUTH_CLIENT_ID: OAuth client ID
- OAUTH_CLIENT_SECRET: OAuth client secret (from Secret Manager)
- OAUTH_REDIRECT_URI: OAuth redirect URI (this function's URL)
- FIREBASE_PROJECT_ID: Firebase project ID
- FIREBASE_STORAGE_BUCKET: Firebase storage bucket

Custom Claims (optional):
- Set CUSTOM_CLAIM_NAME for custom claim extraction (e.g., "national_id")
- This will extract the claim from ID token and add to Firebase custom token
"""

import os
import json
import logging
from typing import Dict, Any, Optional

import requests
import jwt
from jwt import PyJWKClient
from firebase_admin import initialize_app, auth, firestore
from firebase_functions import https_fn, options

# Initialize Firebase Admin SDK
initialize_app()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration from environment variables
# Note: These will be set via Firebase Functions config or Cloud Run environment variables
OAUTH_ISSUER_URL = os.environ.get('OAUTH_ISSUER_URL', '')
OAUTH_CLIENT_ID = os.environ.get('OAUTH_CLIENT_ID', '')
OAUTH_CLIENT_SECRET = os.environ.get('OAUTH_CLIENT_SECRET', '')
OAUTH_REDIRECT_URI = os.environ.get('OAUTH_REDIRECT_URI', '')
CUSTOM_CLAIM_NAME = os.environ.get('CUSTOM_CLAIM_NAME', None)


def exchange_code_for_tokens(code: str, code_verifier: str, redirect_uri: str = None) -> Dict[str, Any]:
    """
    Exchange authorization code for tokens using PKCE verifier.

    Args:
        code: Authorization code from OAuth provider
        code_verifier: PKCE code verifier from frontend
        redirect_uri: Optional redirect URI used during authorization (defaults to OAUTH_REDIRECT_URI)

    Returns:
        Token response containing id_token, access_token, etc.

    Raises:
        requests.HTTPError: If token exchange fails
    """
    token_url = f"{OAUTH_ISSUER_URL}/oidc/token"

    # Use provided redirect_uri or fall back to environment variable
    effective_redirect_uri = redirect_uri or OAUTH_REDIRECT_URI

    payload = {
        'grant_type': 'authorization_code',
        'code': code,
        'code_verifier': code_verifier,
        'client_id': OAUTH_CLIENT_ID,
        'client_secret': OAUTH_CLIENT_SECRET,
        'redirect_uri': effective_redirect_uri
    }

    logger.info(f"Exchanging code for tokens at {token_url}")
    logger.info(f"Using redirect_uri: {effective_redirect_uri}")

    response = requests.post(token_url, data=payload, timeout=10)
    response.raise_for_status()

    return response.json()


def verify_id_token(id_token: str) -> Dict[str, Any]:
    """
    Verify and decode ID token from OAuth provider.

    Args:
        id_token: JWT ID token from OAuth provider

    Returns:
        Decoded token claims

    Raises:
        jwt.InvalidTokenError: If token verification fails
    """
    # Fetch JWKS from OAuth provider
    # Try standard OIDC discovery first, fall back to direct JWKS URL
    jwks_url = f"{OAUTH_ISSUER_URL}/oidc/jwks"
    jwks_client = PyJWKClient(jwks_url)

    # Get signing key from token header
    signing_key = jwks_client.get_signing_key_from_jwt(id_token)

    # Verify and decode token
    decoded_token = jwt.decode(
        id_token,
        signing_key.key,
        algorithms=['RS256'],
        audience=OAUTH_CLIENT_ID,
        issuer=OAUTH_ISSUER_URL
    )

    logger.info(f"Token verified for subject: {decoded_token.get('sub')}")

    return decoded_token


def create_or_update_user(claims: Dict[str, Any]) -> str:
    """
    Create or update user profile in Firestore.

    Args:
        claims: Decoded claims from OAuth provider's ID token

    Returns:
        Firebase Auth UID
    """
    db = firestore.client()

    # Use subject claim as unique identifier
    subject = claims.get('sub')
    if not subject:
        raise ValueError("ID token missing 'sub' claim")

    # Generate Firebase-compatible UID from subject
    # Remove provider prefix if present (e.g., "kenni.is|12345" -> "12345")
    auth_uid = subject.split('|')[-1] if '|' in subject else subject

    # Prepare user profile data
    profile_data = {
        'sub': subject,
        'email': claims.get('email'),
        'name': claims.get('name'),
        'given_name': claims.get('given_name'),
        'family_name': claims.get('family_name'),
        'updated_at': firestore.SERVER_TIMESTAMP
    }

    # Add custom claim if configured
    if CUSTOM_CLAIM_NAME and CUSTOM_CLAIM_NAME in claims:
        profile_data[CUSTOM_CLAIM_NAME] = claims[CUSTOM_CLAIM_NAME]

    # Remove None values
    profile_data = {k: v for k, v in profile_data.items() if v is not None}

    # Create or update user profile
    user_ref = db.collection('users').document(auth_uid)
    user_ref.set(profile_data, merge=True)

    logger.info(f"User profile updated: {auth_uid}")

    return auth_uid


def create_custom_token(uid: str, claims: Dict[str, Any]) -> str:
    """
    Create Firebase custom token with custom claims.

    Args:
        uid: Firebase Auth UID
        claims: Custom claims to include in token

    Returns:
        Custom token (JWT string)
    """
    developer_claims = {}

    # Add custom claim if configured and present
    if CUSTOM_CLAIM_NAME and CUSTOM_CLAIM_NAME in claims:
        developer_claims[CUSTOM_CLAIM_NAME] = claims[CUSTOM_CLAIM_NAME]

    # Create custom token
    custom_token = auth.create_custom_token(
        uid,
        developer_claims=developer_claims if developer_claims else None
    )

    # Decode bytes to string
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
    """
    Cloud Function to handle OAuth callback and create Firebase custom token.

    Request body (JSON):
        - code: Authorization code from OAuth provider
        - codeVerifier: PKCE code verifier from frontend

    Response (JSON):
        - customToken: Firebase custom token for sign-in
        - uid: Firebase Auth UID

    Error Response (JSON):
        - error: Error type
        - message: Error description
    """
    try:
        # Validate configuration at runtime
        if not all([OAUTH_ISSUER_URL, OAUTH_CLIENT_ID, OAUTH_CLIENT_SECRET, OAUTH_REDIRECT_URI]):
            logger.error("Missing required environment variables")
            return https_fn.Response(
                json.dumps({
                    'error': 'configuration_error',
                    'message': 'Cloud Function not properly configured. Check environment variables.'
                }),
                status=500,
                headers={'Content-Type': 'application/json'}
            )

        # Parse request body
        request_json = req.get_json(silent=True)

        if not request_json:
            logger.error("Request body is empty or invalid JSON")
            return https_fn.Response(
                json.dumps({'error': 'invalid_request', 'message': 'Request body must be JSON'}),
                status=400,
                headers={'Content-Type': 'application/json'}
            )

        code = request_json.get('code')
        code_verifier = request_json.get('codeVerifier')
        redirect_uri = request_json.get('redirectUri')

        if not code or not code_verifier:
            logger.error("Missing required parameters")
            return https_fn.Response(
                json.dumps({'error': 'invalid_request', 'message': 'Missing code or codeVerifier'}),
                status=400,
                headers={'Content-Type': 'application/json'}
            )

        logger.info("Processing OAuth callback")

        # Step 1: Exchange authorization code for tokens (with PKCE verifier)
        token_response = exchange_code_for_tokens(code, code_verifier, redirect_uri)
        id_token = token_response.get('id_token')

        if not id_token:
            logger.error("Token response missing id_token")
            return https_fn.Response(
                json.dumps({'error': 'token_error', 'message': 'No ID token received'}),
                status=500,
                headers={'Content-Type': 'application/json'}
            )

        # Step 2: Verify ID token from OAuth provider
        decoded_claims = verify_id_token(id_token)

        # Step 3: Create or update user profile in Firestore
        uid = create_or_update_user(decoded_claims)

        # Step 4: Create Firebase custom token
        custom_token = create_custom_token(uid, decoded_claims)

        # Step 5: Return custom token to frontend
        return https_fn.Response(
            json.dumps({
                'customToken': custom_token,
                'uid': uid
            }),
            status=200,
            headers={'Content-Type': 'application/json'}
        )

    except requests.HTTPError as e:
        logger.error(f"HTTP error during token exchange: {e}")
        logger.error(f"Response: {e.response.text if e.response else 'No response'}")
        return https_fn.Response(
            json.dumps({
                'error': 'token_exchange_failed',
                'message': f'Failed to exchange authorization code: {str(e)}'
            }),
            status=500,
            headers={'Content-Type': 'application/json'}
        )

    except jwt.InvalidTokenError as e:
        logger.error(f"JWT verification error: {e}")
        return https_fn.Response(
            json.dumps({
                'error': 'invalid_token',
                'message': f'ID token verification failed: {str(e)}'
            }),
            status=401,
            headers={'Content-Type': 'application/json'}
        )

    except Exception as e:
        logger.error(f"Unexpected error: {e}", exc_info=True)
        return https_fn.Response(
            json.dumps({
                'error': 'internal_error',
                'message': f'An unexpected error occurred: {str(e)}'
            }),
            status=500,
            headers={'Content-Type': 'application/json'}
        )
