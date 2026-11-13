#!/usr/bin/env bash
#
# release.sh — build MagnetBoard.ipa and publish it as a GitHub Release.
#
# Builds an unsigned .ipa (sideloadable with AltStore / Sideloadly / TrollStore),
# tags the commit, creates the release and uploads:
#
#     MagnetBoard.ipa
#     MagnetBoard.ipa.sha256
#
# Usage:
#   ./release.sh 1.0.0                  # tag v1.0.0, build, upload
#   ./release.sh 1.0.0 --skip-build     # upload an existing build/MagnetBoard.ipa
#   ./release.sh 1.0.0 --draft          # create the release as a draft
#   ./release.sh 1.0.0 --dry-run        # print what would happen
#   ./release.sh 1.0.0 --notes NOTES.md
#   ./release.sh 1.0.0 --repo 1ucent/MagnetBoard
#
# Building needs macOS + Xcode (xcodebuild). Uploading works anywhere.
# Auth, in order of preference: $GH_TOKEN, $GITHUB_TOKEN, `gh auth token`,
# or the credential git already stores for github.com.
#
set -euo pipefail

VERSION=""
SKIP_BUILD=0
DRAFT=""
DRY_RUN=0
NOTES_FILE=""
REPO=""

APP_PATH_BUILD="build/MagnetBoard.ipa"
MODEL="MagnetBoard/Magnet.mfxl"

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; OFF=$'\033[0m'
say()  { printf '%s==>%s %s\n' "$BLUE" "$OFF" "$*"; }
ok()   { printf '%s  +%s %s\n' "$GREEN" "$OFF" "$*"; }
warn() { printf '%s  !%s %s\n' "$YELLOW" "$OFF" "$*" >&2; }
die()  { printf '%sERROR:%s %s\n' "$RED" "$OFF" "$*" >&2; exit 1; }

usage() { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# ---------------------------------------------------------------- arguments ---

while [[ $# -gt 0 ]]; do
  case "$1" in
    [0-9]*.[0-9]*) VERSION="$1"; shift ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --draft)      DRAFT="--draft"; shift ;;
    --dry-run)    DRY_RUN=1; shift ;;
    --notes)      NOTES_FILE="${2:-}"; shift 2 ;;
    --repo)       REPO="${2:-}"; shift 2 ;;
    -h|--help)    usage ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

[[ -n "$VERSION" ]] || die "missing version, e.g. ./release.sh 1.0.0"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || die "version looks wrong: $VERSION"
TAG="v$VERSION"

cd "$(dirname "${BASH_SOURCE[0]}")"

# ---------------------------------------------------------------- repository --

git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
COMMIT="$(git rev-parse --short HEAD)"

if [[ -z "$REPO" ]]; then
  ORIGIN="$(git remote get-url origin 2>/dev/null || true)"
  [[ -n "$ORIGIN" ]] || die "no origin remote; pass --repo owner/name"
  REPO="$(printf '%s' "$ORIGIN" | sed -E 's#^.*github\.com[:/]([^/]+/[^/]+?)(\.git)?$#\1#')"
fi
[[ "$REPO" == */* ]] || die "could not work out the repo slug (got '$REPO')"

say "Releasing $TAG from $BRANCH@$COMMIT to $REPO"

if [[ -n "$(git status --porcelain)" ]]; then
  warn "working tree is dirty — the release will not match the tag"
fi

# --------------------------------------------------------------------- build --

if [[ $SKIP_BUILD -eq 1 ]]; then
  say "Skipping build"
else
  command -v xcodebuild >/dev/null 2>&1 || \
    die "xcodebuild not found: build the .ipa on macOS, or pass --skip-build"

  if [[ ! -f "$MODEL" ]]; then
    warn "MagnetBoard/Magnet.mfxl is missing."
    warn "Without the model the app installs but never sees a magnet (demo mode only)."
    warn "Get it from https://libraries.dev/magnetic (Model tab) before releasing."
  fi

  say "Building unsigned .ipa (this takes a minute)"
  ./build_ipa.sh
fi

[[ -f "$APP_PATH_BUILD" ]] || die "no ipa at $APP_PATH_BUILD (run ./build_ipa.sh first)"
if command -v shasum >/dev/null 2>&1; then
  SHA="$(shasum -a 256 "$APP_PATH_BUILD" | awk '{print $1}')"
else
  SHA="$(sha256sum "$APP_PATH_BUILD" | awk '{print $1}')"
fi
SIZE="$(du -h "$APP_PATH_BUILD" | awk '{print $1}')"
ok "$APP_PATH_BUILD ($SIZE, sha256 ${SHA:0:16}...)"

printf '%s  %s\n' "$SHA" "MagnetBoard.ipa" > "build/MagnetBoard.ipa.sha256"

# ------------------------------------------------------------ release notes --

if [[ -n "$NOTES_FILE" ]]; then
  [[ -f "$NOTES_FILE" ]] || die "notes file not found: $NOTES_FILE"
  NOTES="$(cat "$NOTES_FILE")"
else
  NOTES="MagnetBoard $VERSION - an interface that leans toward a real magnet.

Built with SwiftUI and Magnetic UI / MagnetKit by Libraries.dev.

**Install:** download \`MagnetBoard.ipa\` and sideload it with AltStore,
Sideloadly or TrollStore. It is unsigned.

**Needs:** an iPhone on iOS 17+ and a magnet (a small neodymium ring is best).
\`Magnet.mfxl\` has to be inside the app bundle; a build made without it falls
back to demo mode.

\`\`\`
sha256  $SHA  MagnetBoard.ipa
\`\`\`

Commit $COMMIT on $BRANCH."
fi

# ---------------------------------------------------------------------- auth --

TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -z "$TOKEN" ]] && command -v gh >/dev/null 2>&1; then
  TOKEN="$(gh auth token 2>/dev/null || true)"
fi
if [[ -z "$TOKEN" ]]; then
  TOKEN="$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null | sed -n 's/^password=//p')"
fi
[[ -n "$TOKEN" ]] || die "no GitHub token: export GH_TOKEN=... (repo scope), or run 'gh auth login'"

API="https://api.github.com"
UPLOADS="https://uploads.github.com"
AUTH_HEADER="Authorization: Bearer $TOKEN"

api() { # api METHOD PATH [JSON]
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -sS -X "$method" -H "$AUTH_HEADER" -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" -d "$body" "$API$path"
  else
    curl -sS -X "$method" -H "$AUTH_HEADER" -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" "$API$path"
  fi
}

jget() { # jget KEY — print a key from a JSON object on stdin (empty if missing)
  python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1], ""))' "$1" 2>/dev/null || true
}

if [[ $DRY_RUN -eq 1 ]]; then
  say "Dry run — would:"
  echo "    git tag $TAG && git push origin $TAG"
  echo "    create/refresh release $TAG on $REPO ${DRAFT:+(draft)}"
  echo "    upload $APP_PATH_BUILD and build/MagnetBoard.ipa.sha256"
  exit 0
fi

# ----------------------------------------------------------------------- tag --

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  ok "tag $TAG already exists"
else
  say "Tagging $TAG"
  git tag -a "$TAG" -m "MagnetBoard $VERSION"
fi
git push origin "$TAG" 2>&1 | sed 's/^/    /' || warn "could not push tag (continuing)"

# ------------------------------------------------------------------- release --

notes_body() {
  python3 -c 'import json,sys
print(json.dumps({
    "tag_name": sys.argv[1],
    "name": sys.argv[2],
    "body": sys.stdin.read(),
    "draft": sys.argv[3] == "1",
}))' "$TAG" "MagnetBoard $VERSION" "$([[ -n "$DRAFT" ]] && echo 1 || echo 0)"
}

RELEASE_JSON="$(api GET "/repos/$REPO/releases/tags/$TAG")"
RELEASE_ID="$(printf '%s' "$RELEASE_JSON" | jget id)"
UPLOAD_URL="$(printf '%s' "$RELEASE_JSON" | jget upload_url | sed 's/{.*//')"

if [[ -z "$RELEASE_ID" ]]; then
  say "Creating release $TAG"
  BODY="$(printf '%s' "$NOTES" | notes_body)"
  RELEASE_JSON="$(api POST "/repos/$REPO/releases" "$BODY")"
  RELEASE_ID="$(printf '%s' "$RELEASE_JSON" | jget id)"
  UPLOAD_URL="$(printf '%s' "$RELEASE_JSON" | jget upload_url | sed 's/{.*//')"
  [[ -n "$RELEASE_ID" ]] || die "release creation failed: $RELEASE_JSON"
  ok "release $RELEASE_ID"
else
  say "Release $TAG exists (id $RELEASE_ID) — refreshing notes and assets"
  BODY="$(printf '%s' "$NOTES" | notes_body)"
  api PATCH "/repos/$REPO/releases/$RELEASE_ID" "$BODY" >/dev/null
fi

# ---------------------------------------------------------------- upload ipa --

upload_asset() { # upload_asset FILE CONTENT_TYPE
  local file="$1" type="$2" name existing code
  name="$(basename "$file")"

  existing="$(api GET "/repos/$REPO/releases/$RELEASE_ID/assets?per_page=100" \
    | python3 -c "import json,sys;print(next((a['id'] for a in json.load(sys.stdin) if a['name']==sys.argv[1]),''))" "$name" 2>/dev/null || true)"
  if [[ -n "$existing" ]]; then
    api DELETE "/repos/$REPO/releases/assets/$existing" >/dev/null || true
  fi

  code="$(curl -sS -o /tmp/gh_upload.json -w '%{http_code}' -X POST \
    -H "$AUTH_HEADER" -H "Content-Type: $type" \
    --data-binary "@$file" "$UPLOAD_URL?name=$name")"
  if [[ "$code" == "201" ]]; then
    ok "uploaded $name ($(du -h "$file" | awk '{print $1}'))"
  else
    die "upload of $name failed (HTTP $code): $(head -c 400 /tmp/gh_upload.json)"
  fi
}

upload_asset "$APP_PATH_BUILD" "application/octet-stream"
upload_asset "build/MagnetBoard.ipa.sha256" "text/plain"

# ---------------------------------------------------------------------- done --

printf '\n%sReleased%s https://github.com/%s/releases/tag/%s\n' "$GREEN" "$OFF" "$REPO" "$TAG"
if [[ -n "$DRAFT" ]]; then
  warn "it is a draft — publish it from the releases page when you are ready"
fi
