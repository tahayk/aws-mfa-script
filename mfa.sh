#!/bin/bash
#
# Sample for getting temp session token from AWS STS
#
# aws --profile youriamuser sts get-session-token --duration 3600 \
# --serial-number arn:aws:iam::012345678901:mfa/user --token-code 012345
#
# Once the temp token is obtained, you'll need to feed the following environment
# variables to the aws-cli:
#
# export AWS_ACCESS_KEY_ID='KEY'
# export AWS_SECRET_ACCESS_KEY='SECRET'
# export AWS_SESSION_TOKEN='TOKEN'

AWS_CLI=$(which aws)
if [ $? -ne 0 ]; then
  echo "AWS CLI is not installed; exiting"
  exit 1
else
  echo "Using AWS CLI found at $AWS_CLI"
fi

# A flag to check if the user wants to call post.sh
DO_POST=false

# First, collect all arguments in an array
ARGS=("$@")

# We’ll build a new array of arguments that are not --post
FILTERED_ARGS=()

for arg in "${ARGS[@]}"; do
  if [[ "$arg" == "--post" ]]; then
    DO_POST=true
    # don't add this arg to FILTERED_ARGS
  else
    FILTERED_ARGS+=("$arg")
  fi
done

# Replace positional parameters with the filtered ones
set -- "${FILTERED_ARGS[@]}"

# Now we can handle the remaining arguments (MFA token code and profile).
if [[ $# -ne 1 && $# -ne 2 ]]; then
  echo "Usage: $0 <MFA_TOKEN_CODE> [<AWS_CLI_PROFILE>] [--post]"
  echo "Where:"
  echo "   <MFA_TOKEN_CODE> = Code from virtual MFA device"
  echo "   <AWS_CLI_PROFILE> = aws-cli profile usually in \$HOME/.aws/config"
  echo "   --post (optional) will call post.sh at the end"
  exit 2
fi

SCRIPT_PATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P  )"
MFA_CONFIG="$SCRIPT_PATH/mfa.cfg"

echo "Reading config..."
if [ ! -r "$MFA_CONFIG" ]; then
  echo "No config found. Please create your mfa.cfg. See README.txt for more info."
  exit 2
fi

# If only 1 arg is provided, it's the token code, and we default the profile to "default"
MFA_TOKEN_CODE=$1
AWS_CLI_PROFILE=${2:-default}

ARN_OF_MFA=$(grep "^$AWS_CLI_PROFILE=" "$MFA_CONFIG" | cut -d '=' -f2- | tr -d '"')

echo "AWS-CLI Profile: $AWS_CLI_PROFILE"
echo "MFA ARN: $ARN_OF_MFA"
echo "MFA Token Code: $MFA_TOKEN_CODE"

# Call sts get-session-token
result=$(aws --profile "$AWS_CLI_PROFILE" sts get-session-token --duration 129600 \
             --serial-number "$ARN_OF_MFA" --token-code "$MFA_TOKEN_CODE" --output text) \
       && success=true || success=false
if [ "$success" = false ] ; then
    exit 1
fi

declare $(echo "$result" | awk '{printf("export AWS_ACCESS_KEY_ID=%s\nexport AWS_SECRET_ACCESS_KEY=%s\nexport AWS_SESSION_TOKEN=%s\nexport AWS_SECURITY_TOKEN=%s\n",$2,$4,$5,$5)}' | tee "$HOME/.token_file")

AWS_CLI_PROFILE_TMP="${AWS_CLI_PROFILE}-tmp"
AWS_CLI_REGION=$(aws configure get region --profile "$AWS_CLI_PROFILE")
echo "Setting up a '$AWS_CLI_PROFILE_TMP' AWS profile"
aws configure --profile "$AWS_CLI_PROFILE_TMP" set output json
aws configure --profile "$AWS_CLI_PROFILE_TMP" set region "$AWS_CLI_REGION"
aws configure --profile "$AWS_CLI_PROFILE_TMP" set aws_access_key_id "$AWS_ACCESS_KEY_ID"
aws configure --profile "$AWS_CLI_PROFILE_TMP" set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure --profile "$AWS_CLI_PROFILE_TMP" set aws_session_token "$AWS_SESSION_TOKEN"
# aws configure --profile "$AWS_CLI_PROFILE_TMP" set aws_security_token "$AWS_SECURITY_TOKEN"

wait
echo "'$AWS_CLI_PROFILE_TMP' AWS profile is configured and available for all sessions"

# If --post was passed, invoke post.sh now
if [ "$DO_POST" = true ]; then
  echo "Invoking post.sh..."
  # Either call it directly:
  #   "$SCRIPT_PATH/post.sh"
  # Or source it if needed (so that it runs in the same shell):
  #   source "$SCRIPT_PATH/post.sh"
  #
  # Typically you might just run it:
  "$SCRIPT_PATH/post.sh"
fi
