# How Kitty's Hints Kitten Works

The hints kitten scans the visible terminal screen for matchable text patterns and
overlays selectable labels on them, allowing keyboard-driven interaction.

Workflow

1. Activate — User presses a shortcut (e.g. ctrl+shift+e for URLs).
2. Scan & Label — The kitten scans visible text for matching patterns and overlays
short letter/number labels on each match.
3. Select — User types the label character(s) to select a match (or clicks it with the
mouse).
4. Act — An action is performed on the selected text (open in browser, copy, insert
into terminal, open in editor, etc.).

Supported Match Types

┌───────────┬──────────────────────────────┬──────────────────┐
│   Type    │         Description          │ Default Shortcut │
├───────────┼──────────────────────────────┼──────────────────┤
│ url       │ URLs                         │ ctrl+shift+e     │
├───────────┼──────────────────────────────┼──────────────────┤
│ path      │ File paths                   │ ctrl+shift+p > f │
├───────────┼──────────────────────────────┼──────────────────┤
│ line      │ File paths with line numbers │ ctrl+shift+p > n │
├───────────┼──────────────────────────────┼──────────────────┤
│ hyperlink │ Terminal hyperlinks (OSC 8)  │ ctrl+shift+p > y │
├───────────┼──────────────────────────────┼──────────────────┤
│ word      │ Words                        │ —                │
├───────────┼──────────────────────────────┼──────────────────┤
│ hash      │ Git hashes, etc.             │ —                │
├───────────┼──────────────────────────────┼──────────────────┤
│ regex     │ Custom regex patterns        │ —                │
└───────────┴──────────────────────────────┴──────────────────┘

Key Design Details

- Labels are drawn from a configurable alphabet (default: lowercase letters).
- If there are more matches than single characters, multi-character labels are used
(typed sequentially).
- Mouse clicks on highlighted matches also work.
- The action on selection is configurable: open, copy to clipboard, insert into
terminal, or run a custom program.
- Users can write custom Python scripts for fully custom matching logic and
post-selection behavior.

Relevance to Ghostty

This is essentially the same concept as the URL hint mode you're working on in your
add-url-mode branch — scan visible text, overlay labeled hints, and let the user select
one via keyboard to perform an action (like opening a URL).
