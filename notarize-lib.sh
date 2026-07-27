#!/bin/bash
# Gemeinsame Notarisierungs-Helfer für install.sh und release.sh.
# Wird gesourct, nicht ausgeführt. Credential-Werte bleiben ausschließlich im
# macOS-Schlüsselbund; hier steht nur der Profil-NAME.

# Profilnamen bestimmen: Umgebung schlägt clone-lokale Git-Konfiguration.
# Der Name landet bewusst nicht im öffentlichen Repo — Keychain-Profile sind
# ohnehin pro Mac lokal und werden nicht synchronisiert.
require_notary_profile() {
    if [[ -z "${NOTARY_PROFILE:-}" ]]; then
        NOTARY_PROFILE="$(git config --local --get savageModPlayer.notaryProfile 2>/dev/null || true)"
    fi
    if [[ -z "$NOTARY_PROFILE" ]]; then
        echo "FEHLER: Kein Notary-Profil bekannt." >&2
        echo "Entweder NOTARY_PROFILE setzen oder einmalig für diesen Clone:" >&2
        echo "  git config --local savageModPlayer.notaryProfile <profil>" >&2
        echo "Das Profil selbst einmal pro Mac anlegen:" >&2
        echo "  xcrun notarytool store-credentials <profil> --apple-id <apple-id> --team-id <team-id>" >&2
        return 2
    fi
    export NOTARY_PROFILE

    # Nur ein echter Aufruf erkennt, ob das Profil auf diesem Mac benutzbar ist.
    # Fünf Versuche statt einem: `notarytool history` meldet gelegentlich
    # fälschlich „No Keychain password item found", obwohl das Profil da ist
    # (in einem realen Notary-Lauf beobachtet: Versuch 1 fehlgeschlagen,
    # Versuch 2 war sofort erfolgreich).
    # Ein einzelner Fehlversuch würde sonst einen ganzen Lauf grundlos abbrechen;
    # ein wirklich fehlendes Profil scheitert auch nach fünf Versuchen.
    local attempt
    for attempt in 1 2 3 4 5; do
        xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 && return 0
        sleep 3
    done
    echo "FEHLER: Das Notary-Profil '$NOTARY_PROFILE' ist auf diesem Mac nicht verwendbar." >&2
    echo "Über SSH ist der Login-Schlüsselbund gesperrt — dann in einer lokalen" >&2
    echo "Terminalsitzung erneut versuchen." >&2
    return 2
}

# App-Bundle notarisieren und das Ticket anheften. notarytool nimmt kein nacktes
# .app entgegen, deshalb der Umweg über ein ZIP. Das angeheftete Ticket ist der
# eigentliche Punkt: Damit startet die App auch dann ohne Gatekeeper-Meckern,
# wenn jemand sie aus dem DMG herauszieht oder offline ist.
notarize_app() {
    local app="$1"
    local archive
    archive="$(mktemp -d)/SavageModPlayer.zip"

    if ! codesign --verify --strict "$app" >/dev/null 2>&1; then
        echo "FEHLER: '$app' ist nicht gültig signiert — Notarisierung sinnlos." >&2
        return 1
    fi
    if codesign -dvv "$app" 2>&1 | grep -q '^Signature=adhoc$'; then
        echo "FEHLER: '$app' ist nur ad-hoc signiert. Für die Notarisierung ist eine" >&2
        echo "Developer-ID-Signatur nötig (REQUIRE_CODESIGN=1 bash build_app.sh)." >&2
        return 1
    fi

    echo "=== Notarisiere App (Profil: $NOTARY_PROFILE) ==="
    ditto -c -k --keepParent "$app" "$archive"
    xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl -a -t exec -vv "$app" 2>&1 | tail -2
    rm -rf "$(dirname "$archive")"
}
