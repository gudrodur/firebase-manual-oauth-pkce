#!/bin/bash
#
# Setup Firebase Manual OAuth with PKCE
#
# This script sets up all required Google Cloud resources:
# - Enable required APIs
# - Create Firestore database
# - Create Secret Manager secret for client secret
# - Grant IAM permissions to Cloud Function service account
# - Configure organization policies (if needed)
#
# Usage:
#   ./scripts/setup.sh --project PROJECT_ID --client-secret SECRET [options]
#
# Required:
#   --project PROJECT_ID           Firebase/GCP project ID
#   --client-secret SECRET         OAuth provider client secret
#
# Optional:
#   --region REGION                Cloud Function region (default: europe-west2)
#   --firestore-region REGION      Firestore region (default: europe-west2)
#   --skip-org-policy              Skip organization policy configuration
#   --help                         Show this help message

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
PROJECT=""
CLIENT_SECRET=""
REGION="europe-west2"
FIRESTORE_REGION="europe-west2"
SKIP_ORG_POLICY=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --project)
      PROJECT="$2"
      shift 2
      ;;
    --client-secret)
      CLIENT_SECRET="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --firestore-region)
      FIRESTORE_REGION="$2"
      shift 2
      ;;
    --skip-org-policy)
      SKIP_ORG_POLICY=true
      shift
      ;;
    --help)
      sed -n '2,/^$/p' "$0" | sed 's/^# //'
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Validate required parameters
if [ -z "$PROJECT" ]; then
  echo -e "${RED}Error: --project is required${NC}"
  echo "Use --help for usage information"
  exit 1
fi

if [ -z "$CLIENT_SECRET" ]; then
  echo -e "${RED}Error: --client-secret is required${NC}"
  echo "Use --help for usage information"
  exit 1
fi

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Firebase Manual OAuth with PKCE - Setup                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Project: ${PROJECT}${NC}"
echo -e "${GREEN}Region: ${REGION}${NC}"
echo -e "${GREEN}Firestore Region: ${FIRESTORE_REGION}${NC}"
echo ""

# Get project number
echo -e "${YELLOW}📋 Getting project information...${NC}"
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT" --format="value(projectNumber)")
SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
echo -e "${GREEN}✅ Project Number: ${PROJECT_NUMBER}${NC}"
echo -e "${GREEN}✅ Service Account: ${SERVICE_ACCOUNT}${NC}"

# Enable required APIs
echo -e "\n${YELLOW}🔧 Enabling required APIs...${NC}"
gcloud services enable \
  identitytoolkit.googleapis.com \
  firestore.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  secretmanager.googleapis.com \
  run.googleapis.com \
  --project="$PROJECT"
echo -e "${GREEN}✅ APIs enabled${NC}"

# Create Firestore database
echo -e "\n${YELLOW}💾 Creating Firestore database...${NC}"
if gcloud firestore databases describe --project="$PROJECT" &>/dev/null; then
  echo -e "${GREEN}✅ Firestore database already exists${NC}"
else
  gcloud firestore databases create \
    --location="$FIRESTORE_REGION" \
    --project="$PROJECT"
  echo -e "${GREEN}✅ Firestore database created${NC}"
fi

# Create Secret Manager secret
echo -e "\n${YELLOW}🔐 Creating Secret Manager secret...${NC}"
if gcloud secrets describe oauth-client-secret --project="$PROJECT" &>/dev/null; then
  echo -e "${YELLOW}⚠️  Secret already exists. Adding new version...${NC}"
  echo -n "$CLIENT_SECRET" | gcloud secrets versions add oauth-client-secret \
    --data-file=- \
    --project="$PROJECT"
  echo -e "${GREEN}✅ Secret version added${NC}"
else
  echo -n "$CLIENT_SECRET" | gcloud secrets create oauth-client-secret \
    --data-file=- \
    --replication-policy=automatic \
    --project="$PROJECT"
  echo -e "${GREEN}✅ Secret created${NC}"
fi

# Grant Secret Manager access
echo -e "\n${YELLOW}🔑 Granting Secret Manager access to Cloud Function...${NC}"
gcloud secrets add-iam-policy-binding oauth-client-secret \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role=roles/secretmanager.secretAccessor \
  --project="$PROJECT"
echo -e "${GREEN}✅ Secret Manager access granted${NC}"

# Grant Firestore access
echo -e "\n${YELLOW}💾 Granting Firestore access to Cloud Function...${NC}"
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role=roles/datastore.user \
  --condition=None
echo -e "${GREEN}✅ Firestore datastore.user role granted${NC}"

# Grant Firebase Admin access
echo -e "\n${YELLOW}🔥 Granting Firebase Admin access to Cloud Function...${NC}"
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role=roles/firebase.admin \
  --condition=None
echo -e "${GREEN}✅ Firebase Admin role granted${NC}"

# Grant Service Account Token Creator
echo -e "\n${YELLOW}🎫 Granting Service Account Token Creator role...${NC}"
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role=roles/iam.serviceAccountTokenCreator \
  --condition=None

gcloud iam service-accounts add-iam-policy-binding "$SERVICE_ACCOUNT" \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role=roles/iam.serviceAccountTokenCreator \
  --project="$PROJECT"
echo -e "${GREEN}✅ Service Account Token Creator role granted${NC}"

# Configure organization policy (optional)
if [ "$SKIP_ORG_POLICY" = false ]; then
  echo -e "\n${YELLOW}🏢 Configuring organization policy for public Cloud Run access...${NC}"

  # Create policy file
  cat > /tmp/allow-public-policy.yaml <<EOF
constraint: constraints/iam.allowedPolicyMemberDomains
listPolicy:
  allValues: ALLOW
EOF

  # Try to apply policy
  if gcloud resource-manager org-policies set-policy /tmp/allow-public-policy.yaml \
    --project="$PROJECT" 2>/dev/null; then
    echo -e "${GREEN}✅ Organization policy configured${NC}"
  else
    echo -e "${YELLOW}⚠️  Could not configure organization policy${NC}"
    echo -e "${YELLOW}   This may require organization admin access${NC}"
    echo -e "${YELLOW}   You may need to make Cloud Function public manually${NC}"
  fi

  rm -f /tmp/allow-public-policy.yaml
else
  echo -e "\n${YELLOW}⚠️  Skipping organization policy configuration${NC}"
fi

# Summary
echo -e "\n${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Setup Complete!                                            ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✅ All resources have been configured${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "1. Update functions/.env with your OAuth provider configuration"
echo -e "2. Deploy Cloud Function: ${BLUE}./scripts/deploy.sh --project $PROJECT${NC}"
echo -e "3. Make Cloud Function public: ${BLUE}./scripts/make-public.sh --project $PROJECT${NC}"
echo -e "4. Update OAuth provider redirect URI with Cloud Function URL"
echo ""
