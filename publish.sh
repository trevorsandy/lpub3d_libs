#!/usr/bin/env bash
#
# Author: Trevor SANDY
# Last Update November 14, 2024
#
function ShowHelp() {
    echo
    echo "Script to upload a release asset using the GitHub API v3."
    echo
    echo "Examples:"
    echo
    echo "cd /home/trevorsandy/projects/lpub3d_libs"
	echo 
    echo "env TAG=v1.1.0 DEV_OPS=1 $0"
    echo
	echo "env TAG=v1.1.0 NO_PUBLISH=true $0"
	echo
    echo "env TAG=v1.1.0 COMMIT_NOTE=\"LPub3D Libs v1.1.0\" $0"
    echo
    echo "This script accepts the following parameters:"
	echo
    echo "DEV_OPS      - Build and publish packaged archive to DevOps"
    echo "NO_PUBLISH   - Do not upload DevOps archive to GitHub repository - no tag will be created"
    echo "UNZIP        - Unzip the DevOps build archive package - requires PUBLISH_DEST"
    echo "PUBLISH_DEST - Publish the DevOps build to this destination path"
    echo "TAG          - Release tag"
    echo "OWNER        - GitHub Repository owner"
    echo "RELEASE      - Release label"
    echo "COMMIT_NOTE  - Commit note"
    echo "REPO_NAME    - GitHub Repository"
    echo "REPO_PATH    - Full path to GitHub the repository"
    echo "REPO_BRANCH  - The specified GitHub repository branch"
    echo "ASSET_NAME   - Build archive package file name"
    echo "API_TOKEN    - User GitHub Token (Use a local file containing your token)"
    echo
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help) ShowHelp; exit 0 ;;
        *) echo "Unknown parameter passed: '$1'. Use to show help."; exit 1 ;;
    esac
    shift
done

SCRIPT_NAME=$0
SCRIPT_ARGS=$*
OS_NAME=$(uname)

echo && echo $SCRIPT_NAME && echo

# Check for script dependencies
echo
#set -e
echo -n "Checking dependencies... "
for name in zip unzip jq xargs
do
    [[ $(which $name 2>/dev/null) ]] || { echo -en "\n$name needs to be installed. Use 'sudo apt-get install $name'";deps=1; }
done
[[ $deps -ne 1 ]] && echo "OK" || { echo -en "\nInstall the above and rerun this script\n";exit 1; }

# Validate settings.
[ "$TRACE" ] && set -x

# Arguments
GH_TAG=${TAG:-LATEST}
GH_OWNER=${OWNER:-trevorsandy}
GH_USER=${USER:-trevor}
GH_REPO_NAME=${REPO_NAME:-lpub3d_libs}
GH_REPO_BRANCH=${REPO_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}
GH_REPO_PATH=${REPO_PATH:-/home/$GH_USER/projects/$GH_REPO_NAME}
GH_RELEASE=${RELEASE:-LPub3D Libs $(date +%d.%m.%Y)}
GH_COMMIT_NOTE=${COMMIT_NOTE:-LPub3D Libs ${GH_TAG:1}}
GH_ASSET_NAME=${ASSET_NAME:-3rdParty.zip}
GH_ASSET_SHA_NAME=${GH_ASSET_NAME}.sha256
GH_API_TOKEN=${API_TOKEN:-$(git config --global github.token)}

DEV_OPS_REL=${DEV_OPS:-}
DEV_OPS_NO_PUBLISH=${NO_PUBLISH:-false}
DEV_OPS_REL_UNZIP=${UNZIP:-}
DEV_OPS_PUBLISH_REPO=${DEV_OPS_REPO:-lpub3d-ci}
DEV_OPS_PUBLISH_DEST=${PUBLISH_DEST:-/home/$GH_USER/projects/${DEV_OPS_REPO}/builds}

# Define variables.
GH_DIR="$GH_REPO_PATH/.git"
GH_API="https://api.github.com"
GH_REPO="$GH_API/repos/$GH_OWNER/$GH_REPO_NAME"
GH_TAGS="$GH_REPO/releases/tags/$GH_TAG"
GH_AUTH="Authorization: token $GH_API_TOKEN"
TAG_EXIST=""

# Arguments display
function display_arguments
{
    echo
    echo "--Command Options:"
    [ -n "$SCRIPT_ARGS" ] && \
	echo "--SCRIPT_ARGS...$SCRIPT_ARGS" || true
	[ "$DEV_OPS_NO_PUBLISH" = "true" ] && \
	echo "--TAG.............$GH_TAG - NOT PUBLISHED" || \
	echo "--TAG.............$GH_TAG"
    echo "--OWNER...........$GH_OWNER"
    echo "--REPO_NAME.......$GH_REPO_NAME"
    echo "--REPO_PATH.......$GH_REPO_PATH"
    echo "--REPO_BRANCH.....$GH_REPO_BRANCH"
    echo "--ASSET_NAME......$GH_ASSET_NAME"
    if [ -z "$TAG_EXIST" ]; then
        echo "--RELEASE.........$GH_RELEASE"
        echo "--RELEASE_TYPE....New Release Will Be Created"
    fi
    echo "--COMMIT CHANGES..False"
    if [ -n "$DEV_OPS_REL" ]; then
        DEV_OPS_NO_PUBLISH=true
        echo "--PUBLISH.........Publish Release To Dev Ops"
        [ -n "$DEV_OPS_REL_UNZIP" ] && echo "--Unzip DevOps Release" || true
        echo "--DEV_OPS_DEST....$DEV_OPS_PUBLISH_DEST"
        echo "--DEV_POS_REPO....$DEV_OPS_PUBLISH_REPO"
    fi
    if [ "$DEV_OPS_NO_PUBLISH" = "true" ]; then
        echo "--PUBLISH.........Release Not Published"
        echo "--UPLOAD_TO_GH....False"
    else
        echo "--PUBLISH.........Publish Release To Github"
        echo "--UPLOAD_TO_GH....True"
		echo "--GH_TAGS.........$GH_TAGS"
    fi
    echo
}

# New release data
function generate_release_post_data
{
  cat <<EOF
{
  "tag_name": "$GH_TAG",
  "target_commitish": "$GH_REPO_BRANCH",
  "name": "$GH_RELEASE",
  "body": "$GH_RELEASE_NOTE",
  "draft": false,
  "prerelease": false
}
EOF
}

function mv_exr ()
{
    dir="$2" # Include a / at the end to indicate directory (not filename)
    tmp="$2"; tmp="${tmp: -1}"
    [ "$tmp" != "/" ] && dir="$(dirname "$2")"
    [ -a "$dir" ] ||
    mkdir -p "$dir" &&
    mv "$@"
}

# Package the archive
function package_archive
{
    echo && echo "Creating release package..."
    if [ -f "$GH_ASSET_NAME" ];then
        rm "$GH_ASSET_NAME"
    fi
    cd "$GH_REPO_PATH" || :

    zip -r "$GH_ASSET_NAME" \
    LDGLite-1.3/ \
    LDView-4.5/ \
    lpub3d_trace_cui-3.8/

    echo && echo "Created release package '$GH_ASSET_NAME'" && echo
}

# Set working directory
cd "$GH_REPO_PATH" || :

# Logger
ME="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
CWD=$(pwd)
f="${CWD}/$ME"
ext=".log"
if [[ -e "$f$ext" ]] ; then
    i=1
    f="${f%.*}";
    while [[ -e "${f}_${i}${ext}" ]]; do
      let i++
    done
    f="${f}_${i}${ext}"
    else
    f="${f}${ext}"
fi
# Output log file
LOG="$f"
exec > >(tee -a ${LOG} )
exec 2> >(tee -a ${LOG} >&2)

# Get tag
GIT_DIR=$GH_REPO_PATH/.git git fetch --tags
VER_TAG=$(GIT_DIR=$GH_REPO_PATH/.git git describe --tags --match v* --abbrev=0)
if [[ "$GH_TAG" == 'LATEST' ]]; then
    echo && echo -n "Setting latest tag... "
    GH_TAGS="$GH_REPO/releases/latest"
    GH_TAG=$VER_TAG
    TAG_EXIST=$GH_TAG
    echo "$VER_TAG"
else
    echo && echo -n "Getting specified tag... "
    VER_TAG=$GH_TAG
    if GIT_DIR=$GH_REPO_PATH/.git git rev-parse $GH_TAG >/dev/null 2>&1; then
        TAG_EXIST=$GH_TAG
        echo "$VER_TAG"
    else
        echo tag "$VER_TAG" not found - will be created.
    fi
fi

# Show options
display_arguments

# Confirmation
sleep 1s && read -p "  Are you sure (y/n)? " -n 1 -r
echo    # (optional) move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]];then
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
fi
echo
# Validate API Token [Place token in git config "git config --global github.token YOUR_TOKEN"]
[[ -z "$GH_API_TOKEN" ]] && echo && echo "GH_API_TOKEN not specified. Exiting." && exit 1

# Convert line endings
echo -n "Converting files from CRLF to LF..." && \
( find . \
-not -path "./.git/*" \
-not -path "./.vscode/*" \
-not -path "./LDGLite-1.3/bin/*" \
-not -path "./LDView-4.5/bin/*" \
-not -path "./lpub3d_trace_cui-3.8/bin/*" \
-not -name '*.cat' \
-not -name '*.ttf' \
-not -name '*.png' \
-not -name '*.map' \
-not -name '*.df3' \
-not -name '*.pot' \
-not -name '*.chm' \
-type f -print0 | xargs -0 dos2unix -q ) && \
echo "Done" || echo "Failed"


# Package the archive
package_archive

if [[ -n $DEV_OPS_REL && -f $GH_ASSET_NAME ]]; then
    declare -r p=Publish
    DEV_OPS_PUBLISH_SRC=$PWD
    DEV_OPS_NO_PUBLISH=true
    echo -n "Publish package '$GH_ASSET_NAME' to Dev Ops..." && \
    ([ -d "$DEV_OPS_PUBLISH_DEST" ] || mkdir -p "$DEV_OPS_PUBLISH_DEST"; \
     cd "$DEV_OPS_PUBLISH_DEST" && cp -f "$DEV_OPS_PUBLISH_SRC/$GH_ASSET_NAME" .; \
     [ -n "$DEV_OPS_REL_UNZIP" ] && unzip -o "$GH_ASSET_NAME" && rm -rf "$GH_ASSET_NAME" || true) >$p.out 2>&1 && rm $p.out
    [ -f $p.out ] && echo "ERROR - failed to publish $GH_ASSET_NAME to Dev Ops" && tail -80 $p.out || echo "Success." && \
    echo "Publish Destination: $DEV_OPS_PUBLISH_DEST"
fi

# Commit changed files
echo && echo "Commit changed files..."
git add .
cat << pbEOF >$GH_DIR/COMMIT_EDITMSG
$GH_COMMIT_NOTE

pbEOF
GIT_DIR=$GH_REPO_PATH/.git git commit -m "$GH_COMMIT_NOTE"

# Stop here if not uploading build
if [ "$DEV_OPS_NO_PUBLISH" = "true" ]; then echo && echo "Finished." && echo && exit 0; fi

# Set latest tag or create release tag if specified tag does not exist
if [[ -z "$TAG_EXIST" ]]; then
    echo && echo "Create release '$GH_RELEASE', version '$GH_TAG', for repo '$GH_REPO_NAME' on branch '$GH_REPO_BRANCH'" && echo
    curl -H "$GH_AUTH" --data "$(generate_release_post_data)" "$GH_REPO/releases"
    GIT_DIR=$GH_REPO_PATH/.git git fetch --tags
    VER_TAG=$(GIT_DIR=$GH_REPO_PATH/.git git describe --tags --match v* --abbrev=0)
fi
# VER_TAG=$GH_TAG    #ENABLE FOR TEST
echo && echo "Retrieved tag: '$GH_TAG'" && echo

# Validate token.
echo "Validating user token..." && echo
curl -o /dev/null -sH "$GH_AUTH" $GH_REPO || { echo "ERROR: Invalid repo, token or network issue!";  exit 1; }

# Read asset tags and display response.
echo "Retrieving repository data..." && echo
GH_RESPONSE=$(curl -sH "$GH_AUTH" $GH_TAGS)
echo "INFO: Response $GH_RESPONSE" && echo

# Release was not found so create it
GH_RELEASE_NOT_FOUND=$(echo -e "$GH_RESPONSE" | sed -n '2p')
if [[ "$GH_RELEASE_NOT_FOUND" == *"Not Found"* ]]; then
    echo && echo "Release not found. Creating release '$GH_RELEASE', version '$GH_TAG', for repo '$GH_REPO_NAME' on branch '$GH_REPO_BRANCH'..." && echo
    GH_COMMIT_NOTE=$(git log -1 --pretty=%B)
    curl -H "$GH_AUTH" --data "$(generate_release_post_data)" "$GH_REPO/releases"
    GH_RESPONSE=$(curl -sH "$GH_AUTH" $GH_TAGS)
fi

# Get ID of the release.
echo && echo -n "Retrieving release id... "
GH_RELEASE_ID="$(echo $GH_RESPONSE | jq -r .id)"
echo "Release id: '$GH_RELEASE_ID'"

# Get ID of the asset based on given file name.
echo && echo -n "Retrieving asset id... "
GH_ASSET_ID="$(echo $GH_RESPONSE | jq -r '.assets[] | select(.name == '\"$GH_ASSET_NAME\"').id')"
if [ "$GH_ASSET_ID" = "" ]; then
    echo "Asset id for $GH_ASSET_NAME not found so no need to overwrite"
else
    echo "Asset id: '$GH_ASSET_ID'" && echo
    echo "Deleting asset $GH_ASSET_NAME ($GH_ASSET_ID)..."
    curl -X "DELETE" -H "$GH_AUTH" "$GH_REPO/releases/assets/$GH_ASSET_ID"
fi

# Get ID of the asset sha based on given file name.
echo && echo -n "Retrieving asset sha id... "
GH_ASSET_SHA_ID="$(echo $GH_RESPONSE | jq -r '.assets[] | select(.name == '\"$GH_ASSET_SHA_NAME\"').id')"
if [ "$GH_ASSET_SHA_ID" = "" ]; then
    echo "Asset id for $GH_ASSET_SHA_NAME not found so no need to overwrite"
else
    echo "Asset id: '$GH_ASSET_SHA_ID'" && echo
    echo "Deleting asset sha $GH_ASSET_SHA_NAME ($GH_ASSET_SHA_ID)..."
    curl -X "DELETE" -H "$GH_AUTH" "$GH_REPO/releases/assets/$GH_ASSET_SHA_ID"
fi

# Prepare SHA hash file
echo && echo -n "Creating $GH_ASSET_SHA_NAME hash file..."
sha256sum "$GH_ASSET_NAME" > "$GH_ASSET_SHA_NAME" && echo "OK" || \
echo "ERROR - Failed"

# Prepare and upload the asset and respective asset sha files
if [[ -f "$GH_ASSET_NAME" && -f "$GH_ASSET_SHA_NAME" ]]; then

echo && echo "Uploading asset sha $GH_ASSET_SHA_NAME, ID: $GH_ASSET_SHA_ID..."

GH_ASSET_URL=https://uploads.github.com/repos/$GH_OWNER/$GH_REPO_NAME/releases/$GH_RELEASE_ID/assets

GH_ASSET="${GH_ASSET_URL}?name=$(basename "$GH_ASSET_NAME").sha256"

curl --data-binary @"$GH_ASSET_SHA_NAME" -H "$GH_AUTH" -H "Content-Type: application/x-www-form-urlencoded" "$GH_ASSET"

echo && echo "Uploading asset $GH_ASSET_NAME, ID: $GH_ASSET_ID..."

GH_ASSET="${GH_ASSET_URL}?name=$(basename "$GH_ASSET_NAME")"

curl --data-binary @"$GH_ASSET_NAME" -H "$GH_AUTH" -H "Content-Type: application/octet-stream" "$GH_ASSET"

else

echo && echo "ERROR - Could not find $GH_ASSET_SHA_NAME or $GH_ASSET_NAME - No upload performed."

fi

echo && echo "Finished." && echo