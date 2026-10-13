# Simulator UI failures: October 13

The supplied Codemagic log reports 246 unit tests passing and four UI tests failing. The final exit 124 followed a 180-second runner transition timeout after the UI suite failed; it was not a compilation error or a unit-test failure.

The first-item test without the opening animation tapped the item category control, but the captured accessibility tree shows `Belongs to` with a `Category` back button. The category Picker and ownership NavigationLink were both inside the same Form row's VStack. They now occupy separate native rows within the existing stable-ID ForEach. Names, amounts and quantity stay together; draft bindings and validation are unchanged. Both item-editing UI flows now assert that a category tap opens Category without also opening ownership.

The opening-enabled test logged an AVAudioSession warning about main-thread unresponsiveness, followed by idle/snapshot timeouts. Saving also stalled. FeedbackSounds previously activated/deactivated the audio session and prepared AVAudioPlayer synchronously on the main actor, including at launch and save. These operations now run on a separate actor. Playback and stop requests carry increasing revisions to reject stale requests; delayed cleanup only releases the matching cue. Preferences and foreground checks stay on the main actor. Audio is not disabled for tests. This removes an identified blocking path; the log alone cannot prove it caused every timeout.

Local validation: project integrity and changed Swift syntax. Native compilation and all four UI tests must be rerun on macOS to verify these fixes. Test time limits and success gates are unchanged.
