# oob-usb-serial login auto-attach snippet
#
# When installed into the OOB user's shell profile, logging in as that user
# attaches straight to the shared serial console session (creating it first if
# it is not already running). Detaching from screen (Ctrl-a d) then logs out.
#
# This is OPT-IN. The package installs it to:
#   /usr/share/oob-usb-serial/profile/oob-usb-serial.sh
# Enable it for the OOB user by symlinking or sourcing it from their profile,
# e.g.:
#   ln -s /usr/share/oob-usb-serial/profile/oob-usb-serial.sh \
#         /home/oob/.profile.d/oob-usb-serial.sh
# or append to ~/.bash_profile:
#   . /usr/share/oob-usb-serial/profile/oob-usb-serial.sh

# Only act on real interactive login shells, and never when already inside
# screen (avoids recursive nesting).
# shellcheck disable=SC2317  # the bail-out branch is reached in non-interactive shells
case "$-" in
    *i*) ;;
    *) return 2>/dev/null || exit ;;
esac

if [ -z "${STY:-}" ] && command -v oob-usb-serial >/dev/null 2>&1; then
    # Attach (starts the session if needed). On detach, the login shell
    # continues; add 'exit' after this line in the profile if you want detach
    # to log the user out entirely.
    oob-usb-serial attach
fi
