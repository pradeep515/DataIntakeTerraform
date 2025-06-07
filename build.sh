#/bin/sh
# rm -f lambda_function.zip
LAMBDA_DIR="lambda"
LATEST_FILE=$(ls ${LAMBDA_DIR}/lambda_function_v*.zip 2>/dev/null | sort -V | tail -n 1)

if [[ -z "$LATEST_FILE" ]]; then
  # If no file found, start at version 0.0.1
  VERSION="0.0.1"
else
  # Extract version number from filename
  VERSION=$(echo "$LATEST_FILE" | sed -E 's/^.*_v([0-9]+\.[0-9]+\.[0-9]+)\.zip$/\1/')

  # Split version into parts
  IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"

  # Increment patch version
  PATCH=$((PATCH + 1))

  # Rebuild version string
  VERSION="$MAJOR.$MINOR.$PATCH"
fi
ZIP_NAME="lambda_function_v$VERSION.zip"
zip -r lambda/${ZIP_NAME} lambda_function.py boto3
