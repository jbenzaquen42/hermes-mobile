# Hermes Control baseline

This fork starts from Hermes Mobile commit
`af717c53a474566b85f81203117409486073d242`. At bootstrap time that commit was also
the head of `goncharik/hermes-mobile` `main`, so there was no upstream delta to merge.

## Repository layout

- `origin`: `https://github.com/jbenzaquen42/hermes-mobile.git`
- `upstream`: `https://github.com/goncharik/hermes-mobile.git`
- App bundle identifier: `com.jbenzaquen.hermesioscontrol`
- Test bundle identifier: `com.jbenzaquen.hermesioscontrol.tests`
- Installed display name: `Hermes Control`

The Xcode target and scheme retain the upstream `HermesMobile` name to keep the first
device build focused on signing and runtime verification rather than a broad rename.

## Mac verification gate

Run these from the repository root on a Mac with Xcode 26+ and Tuist installed:

```sh
make setup
make test
make build
DEVELOPMENT_TEAM=<10-character-team-id> make run-device
```

The device launcher derives the bundle identifier from Xcode build settings, so it
stays correct if the identifier changes again.

Before feature development is considered validated, confirm on the target iPhone:

1. Login to the existing Hermes dashboard succeeds.
2. Existing sessions load and a new chat can be created.
3. A response streams successfully.
4. The same response remains correct across background and foreground transitions.
5. Record the Hermes server version and the `session.info` desktop contract.

Windows can verify source history, remotes, diffs, and shell syntax, but it cannot run
Tuist, Xcode, iOS tests, signing, installation, or the physical-device checks above.

## Signing caveat

The upstream app includes the APNs entitlement and remote-notification background mode.
A paid Apple Developer team should be able to retain them. A Personal Team may require
a separate push-disabled generation option before the first device build; do not remove
the push integration globally just to make that local configuration work.
