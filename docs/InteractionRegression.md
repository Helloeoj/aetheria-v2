# Fishing modal and developer access repair — 2026-10-22

The account/world installation introduced an invisible online activity modal.
Pressing F opened it and blocked gameplay, while Escape closed it. The app and
chat still processed input. Three failures were reproduced through native input:

- The panel used physical viewport coordinates beneath an already scaled UI
  parent. Its initial wrapped-label layout could also retain an excessively tall
  container size, placing controls outside the visible window.
- The game consumed mouse events before Godot could dispatch them to activity
  buttons.
- Chat's Enter-key handler did not recognize the online activity as a modal.

The panel now sizes and positions itself in its parent's logical coordinates,
shrinks back to the current content minimum, receives GUI clicks, and retains
Enter for its activity action. Native tests cover F, visible bounds, mouse input,
Enter, Escape, resumed movement and deliberate chat typing at 1280×720,
2560×1440 and 3840×2160.

Login now exposes the original developer sandbox explicitly. Tests verify all
developer hotkeys and prevent authenticated online characters from entering the
sandbox without logging out. Automatic goblin encounters were removed from
production startup and moved to explicit combat test fixtures.

The initially prepared ADC report contained an external process-exit observation,
not a stack trace establishing a crash. This repair addresses the reproduced
invisible-modal/input lock; it does not mark unrelated exit observations resolved.
