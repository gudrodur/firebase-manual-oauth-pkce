#!/bin/bash
#
# Deploy Firebase Manual OAuth with PKCE
#
# This script deploys the Cloud Function and optionally the frontend.
#
# Usage:
#   ./scripts/deploy.sh [options]
#
# Options:
#   --function-only    Deploy only Cloud Function
#   --hosting-only     Deploy only Firebase Hosting
#   --project PROJECT  Firebase project ID (default: from .firebaserc)
#   --region REGION    Cloud Function region (default: europe-west2)
#   --help            Show this help message

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
DEPLOY_FUNCTION=true
DEPLOY_HOSTING=true
REGION="europe-west2"
PROJECT=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --function-only)
      DEPLOY_HOSTING=false
      shift
      ;;
    --hosting-only)
      DEPLOY_FUNCTION=false
      shift
      ;;
    --project)
      PROJECT="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --help)
      sed -n '2,/^$/p' "$0" | sed 's/^# //'
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      exit 1
      ;;
  esac
done

# Determine project ID
if [ -z "$PROJECT" ]; then
  if [ -f .firebaserc ]; then
    PROJECT=$(jq -r '.projects.default' .firebaserc 2>/dev/null || echo "")
  fi

  if [ -z "$PROJECT" ]; then
    echo -e "${RED}Error: Could not determine project ID${NC}"
    echo "Specify with --project or run 'firebase use' first"
    exit 1
  fi
fi

echo -e "${GREEN}Deploying to project: ${PROJECT}${NC}"

# Deploy Cloud Function
if [ "$DEPLOY_FUNCTION" = true ]; then
  echo -e "\n${YELLOW}📦 Deploying Cloud Function...${NC}"

  # Check if functions directory exists
  if [ ! -d "functions" ]; then
    echo -e "${RED}Error: functions/ directory not found${NC}"
    exit 1
  fi

  # Check if requirements.txt exists
  if [ ! -f "functions/requirements.txt" ]; then
    echo -e "${RED}Error: functions/requirements.txt not found${NC}"
    exit 1
  fi

  # Deploy function
  firebase deploy --only functions:handleOAuthCallback --project="$PROJECT"

  # Get function URL
  FUNCTION_URL=$(gcloud functions describe handleOAuthCallback \
    --region="$REGION" \
    --project="$PROJECT" \
    --format="value(serviceConfig.uri)" 2>/dev/null || echo "")

  if [ -n "$FUNCTION_URL" ]; then
    echo -e "${GREEN}✅ Cloud Function deployed successfully${NC}"
    echo -e "${GREEN}URL: ${FUNCTION_URL}${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  Important: Update your OAuth provider redirect URI to:${NC}"
    echo -e "${YELLOW}   ${FUNCTION_URL}${NC}"
  else
    echo -e "${RED}❌ Failed to get Cloud Function URL${NC}"
    exit 1
  fi
fi

# Deploy Firebase Hosting
if [ "$DEPLOY_HOSTING" = true ]; then
  echo -e "\n${YELLOW}🌐 Deploying Firebase Hosting...${NC}"

  # Check if public directory exists
  if [ ! -d "public" ]; then
    echo -e "${YELLOW}Warning: public/ directory not found${NC}"
    echo -e "${YELLOW}Skipping hosting deployment${NC}"
  else
    firebase deploy --only hosting --project="$PROJECT"

    # Get hosting URL
    HOSTING_URL="https://${PROJECT}.web.app"

    echo -e "${GREEN}✅ Firebase Hosting deployed successfully${NC}"
    echo -e "${GREEN}URL: ${HOSTING_URL}${NC}"
  fi
fi

echo -e "\n${GREEN}🎉 Deployment complete!${NC}"
