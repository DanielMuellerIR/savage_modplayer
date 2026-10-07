#!/usr/bin/env bash
#
# publish_github.sh — Erstveroeffentlichung und Releases fuer GitHub.
#
# Das Skript pusht nur Code, wenn der Arbeitsbaum sauber ist und keine
# Audio-/Release-Artefakte im Git-Index liegen. Releases erzeugt es optional
# ueber GitHub CLI. Es legt keine gesonderten KI-Contributor an; GitHub zeigt
# nur den normalen Git-/GitHub-Account, der den Push ausfuehrt.
#
# Aufruf:
#   bash publish_github.sh                       # Code pushen
#   bash publish_github.sh --release             # Code pushen + Release/DMG
#   bash publish_github.sh --dry-run --release   # Checks anzeigen, nichts pushen
#
# Umgebung:
#   REMOTE_URL      GitHub-URL, muss dem effektiven Push-Ziel des Remotes github entsprechen.
#   BRANCH          Zielbranch, Default: main.
#   REQUIRE_CLEAN   1 = sauberer Arbeitsbaum Pflicht, Default: 1.

set -euo pipefail

REMOTE_URL="${REMOTE_URL:-https://github.com/DanielMuellerIR/savage_modplayer.git}"
BRANCH="${BRANCH:-main}"
REQUIRE_CLEAN="${REQUIRE_CLEAN:-1}"
VERSION="$(cat VERSION 2>/dev/null || echo "0.0.0")"
TAG="v${VERSION}"
DMG_PATH="build/Savage Mod Player.dmg"
DO_RELEASE=0
DRY_RUN=0

usage() {
    cat <<EOF
Usage: bash publish_github.sh [--release] [--dry-run]

  --release  Create or update GitHub release ${TAG} and upload the DMG.
  --dry-run  Run checks and print planned actions without pushing.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)
            DO_RELEASE=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

run() {
    if [[ "$DRY_RUN" == "1" ]]; then
        printf 'DRY-RUN:'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

if [[ "$REQUIRE_CLEAN" == "1" ]] && [[ -n "$(git status --short --untracked-files=all)" ]]; then
    echo "ABBRUCH: Arbeitsbaum nicht sauber. Erst committen oder REQUIRE_CLEAN=0 setzen." >&2
    git status --short --untracked-files=all >&2
    exit 1
fi

# Die Single-File-HTML wird aus src/ generiert und bettet u.a. VERSION ein.
# Veraltet gepushter Stand laesst den CI-Check "HTML ist aktuell" fehlschlagen
# (passiert bei 1.4.0/1.4.1 nach VERSION-Bumps). Deshalb hier regenerieren und
# bei Abweichung abbrechen — committen bleibt bewusst ein manueller Schritt.
python3 build.py >/dev/null
if [[ -n "$(git status --short -- savage-mod-player.html)" ]]; then
    echo "ABBRUCH: savage-mod-player.html war veraltet (build.py hat sie gerade regeneriert)." >&2
    echo "Diff pruefen, committen und publish_github.sh erneut starten." >&2
    exit 1
fi

# Nur getrackte Dateien koennen auf GitHub landen. Deshalb reicht git ls-files
# als harter Schutz gegen Testmusik und lokale Release-Artefakte.
FORBIDDEN="$(git ls-files | grep -E -i '(^audio/|\.mod$|\.s3m$|\.xm$|\.it$|\.sid$|\.AppImage$|\.wav$|\.aiff?$|\.mp3$|\.flac$|\.dmg$|\.app/|\.zip$|\.tar(\.gz)?$)' || true)"
if [[ -n "$FORBIDDEN" ]]; then
    echo "ABBRUCH: Nicht veroeffentlichbare Artefakte sind getrackt:" >&2
    echo "$FORBIDDEN" >&2
    exit 1
fi

if [[ "$DO_RELEASE" == "1" ]]; then
    if [[ ! -f "$DMG_PATH" ]]; then
        echo "ABBRUCH: DMG fehlt: $DMG_PATH" >&2
        echo "Vorher ausfuehren: bash build_app.sh && bash build_dmg.sh --notarize" >&2
        exit 1
    fi
    if ! command -v gh >/dev/null 2>&1; then
        echo "ABBRUCH: GitHub CLI 'gh' fehlt. Fuer Releases installieren oder manuell hochladen." >&2
        exit 1
    fi
fi

# Das Ziel wird aus genau dieser URL bestimmt; Repo-Konfiguration und GH_REPO
# dürfen den freigegebenen Push oder Asset-Upload nicht umleiten.
if [[ "$REMOTE_URL" =~ ^https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)(\.git)?$ ]]; then
    GH_TARGET="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
elif [[ "$REMOTE_URL" =~ ^git@github\.com:([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)(\.git)?$ ]]; then
    GH_TARGET="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
else
    echo "ABBRUCH: Erwartet wird eine GitHub-Repository-URL ohne Credentials." >&2
    exit 1
fi
EFFECTIVE_URLS="$(git remote get-url --push --all github)" || {
    echo "ABBRUCH: Git-Remote github muss für das gewünschte Ziel konfiguriert sein." >&2; exit 1;
}
[[ "$EFFECTIVE_URLS" == "$REMOTE_URL" ]] || {
    echo "ABBRUCH: Git-URL-Umschreibung verändert das Veröffentlichungsziel." >&2; exit 1;
}
git check-ref-format "refs/heads/$BRANCH" >/dev/null
git check-ref-format "refs/tags/$TAG" >/dev/null
RELEASE_COMMIT="$(git rev-parse HEAD)"
LOCAL_BRANCH="$(git symbolic-ref --quiet HEAD)" || {
    echo "ABBRUCH: Release benötigt einen lokalen Branch." >&2; exit 1;
}

if [[ "$DO_RELEASE" == "1" ]]; then
    if git show-ref --verify --quiet "refs/tags/$TAG"; then
        [[ "$(git rev-parse "refs/tags/$TAG^{commit}")" == "$RELEASE_COMMIT" ]] || {
            echo "ABBRUCH: Lokaler Versionstag zeigt auf einen anderen Commit." >&2; exit 1;
        }
    fi
    REMOTE_TAGS="$(git ls-remote "$REMOTE_URL" "refs/tags/$TAG" "refs/tags/$TAG^{}")"
    if [[ -n "$REMOTE_TAGS" ]]; then
        REMOTE_COMMIT="$(printf '%s\n' "$REMOTE_TAGS" | awk '$2 ~ /\^\{\}$/ {peeled=$1} $2 !~ /\^\{\}$/ {direct=$1} END {print peeled ? peeled : direct}')"
        [[ "$REMOTE_COMMIT" == "$RELEASE_COMMIT" ]] || {
            echo "ABBRUCH: Entfernter Versionstag zeigt auf einen anderen Commit." >&2; exit 1;
        }
    fi
fi

if [[ "$DO_RELEASE" == "1" ]]; then
    ASSETS=("$DMG_PATH" "savage-mod-player.html")
    APPIMAGE="build/linux/Savage-Mod-Player-${VERSION}-x86_64.AppImage"
    if [[ -f "$APPIMAGE" ]]; then
        [[ -f "$APPIMAGE.sha256" ]] || { echo "AppImage-Prüfsumme fehlt." >&2; exit 1; }
        (cd "$(dirname "$APPIMAGE")" && shasum -a 256 -c "$(basename "$APPIMAGE").sha256")
        ASSETS+=("$APPIMAGE" "$APPIMAGE.sha256")
    fi
fi

echo "GitHub: $GH_TARGET; Branch: $BRANCH"
run git push --no-follow-tags "$REMOTE_URL" "$LOCAL_BRANCH:refs/heads/$BRANCH"

if [[ "$DO_RELEASE" == "1" ]]; then
    if ! git show-ref --verify --quiet "refs/tags/$TAG"; then
        run git tag -a "$TAG" "$RELEASE_COMMIT" -m "Savage Mod Player ${VERSION}"
    fi
    run git push --no-follow-tags "$REMOTE_URL" "refs/tags/$TAG:refs/tags/$TAG"
    if [[ "$DRY_RUN" != "1" ]]; then
        REMOTE_TAGS="$(git ls-remote "$REMOTE_URL" "refs/tags/$TAG" "refs/tags/$TAG^{}")"
        [[ "$(printf '%s\n' "$REMOTE_TAGS" | awk '$2 ~ /\^\{\}$/ {peeled=$1} $2 !~ /\^\{\}$/ {direct=$1} END {print peeled ? peeled : direct}')" == "$RELEASE_COMMIT" ]] || {
            echo "ABBRUCH: Entfernten Release-Commit nicht bestätigt." >&2; exit 1;
        }
    fi
    if gh release view "$TAG" -R "$GH_TARGET" >/dev/null 2>&1; then
        run gh release upload "$TAG" -R "$GH_TARGET" "${ASSETS[@]}" --clobber
    else
        run gh release create "$TAG" -R "$GH_TARGET" --verify-tag "${ASSETS[@]}" \
            --title "Savage Mod Player ${VERSION}" --notes-file RELEASE_NOTES.md
    fi
fi

echo "Fertig."
