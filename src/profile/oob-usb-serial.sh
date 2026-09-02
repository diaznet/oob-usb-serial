# oob-usb-serial login auto-attach snippet
#
# When installed into the OOB user's shell profile, logging in as that user
# attaches straight to the shared serial console session (creating it first if
# it is not already running). Detaching from tmux (Ctrl-b d) then returns to
# the shell.
#
# This is OPT-IN. The package installs it to:
#   /usr/share/oob-usb-serial/profile/oob-usb-serial.sh
# Enable it for the OOB user by sourcing it from their profile, e.g. append to
# ~/.bash_profile:
#   . /usr/share/oob-usb-serial/profile/oob-usb-serial.sh

# Only act on real interactive shells, and never when already inside tmux
# (avoids recursive nesting when the session itself spawns shells).
# shellcheck disable=SC2317  # the bail-out branch is reached in non-interactive shells
case "$-" in
    *i*) ;;
    *) return 2>/dev/null || exit ;;
esac

if [ -z "${TMUX:-}" ] && command -v oob-usb-serial >/dev/null 2>&1; then
    # Attach (starts the session if needed). On detach, the login shell
    # continues; add 'exit' after this line in the profile if you want detach
    # to log the user out entirely.
    oob-usb-serial attach
fi
