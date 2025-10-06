#!/bin/bash
#
# Make Cloud Function publicly accessible
#
# This script makes the handleOAuthCallback Cloud Function publicly accessible
# by granting the Cloud Run Invoker role to allUsers.
#
# Usage:
#   ./scripts/make-public.sh --project PROJECT_ID [options]
#
# Required:
#   --project PROJECT_ID    Firebase/GCP project ID
#
# Optional:
#   --region REGION         Cloud Function region (default: europe-west2)
#   --help                  Show this help message

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
PROJECT=""
REGION="europe-west2"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
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

echo -e "${YELLOW}🔓 Making Cloud Function publicly accessible...${NC}"
echo -e "${GREEN}Project: ${PROJECT}${NC}"
echo -e "${GREEN}Region: ${REGION}${NC}"
echo ""

# Method 1: Try gcloud functions add-invoker-policy-binding
echo -e "${YELLOW}Attempting method 1: gcloud functions...${NC}"
if gcloud functions add-invoker-policy-binding handleOAuthCallback \
  --region="$REGION" \
  --member=allUsers \
  --project="$PROJECT" 2>/dev/null; then
  echo -e "${GREEN}✅ Cloud Function is now publicly accessible (method 1)${NC}"
  exit 0
fi

echo -e "${YELLOW}Method 1 failed, trying method 2...${NC}"

# Method 2: Try gcloud run services add-iam-policy-binding
echo -e "${YELLOW}Attempting method 2: gcloud run services...${NC}"
if gcloud run services add-iam-policy-binding handleoauthcallback \
  --region="$REGION" \
  --member=allUsers \
  --role=roles/run.invoker \
  --project="$PROJECT" 2>/dev/null; then
  echo -e "${GREEN}✅ Cloud Function is now publicly accessible (method 2)${NC}"
  exit 0
fi

echo -e "${YELLOW}Method 2 failed, trying method 3...${NC}"

# Method 3: Use IAM policy file
echo -e "${YELLOW}Attempting method 3: IAM policy file...${NC}"

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

if gcloud run services set-iam-policy handleoauthcallback \
  /tmp/run-policy.json \
  --region="$REGION" \
  --project="$PROJECT" \
  --quiet 2>/dev/null; then
  rm -f /tmp/run-policy.json
  echo -e "${GREEN}✅ Cloud Function is now publicly accessible (method 3)${NC}"
  exit 0
fi

# All methods failed
rm -f /tmp/run-policy.json
echo -e "${RED}❌ Failed to make Cloud Function public${NC}"
echo ""
echo -e "${YELLOW}This may be due to an organization policy.${NC}"
echo -e "${YELLOW}Try the following:${NC}"
echo ""
echo -e "1. Ask your organization admin to modify the policy:"
echo -e "   ${GREEN}gcloud resource-manager org-policies set-policy allow-public-policy.yaml --project=$PROJECT${NC}"
echo ""
echo -e "2. Or manually update the IAM policy in Cloud Console:"
echo -e "   ${GREEN}https://console.cloud.google.com/run/detail/${REGION}/handleoauthcallback/permissions?project=${PROJECT}${NC}"
echo ""
echo -e "See docs/TROUBLESHOOTING.md for more information."
exit 1
