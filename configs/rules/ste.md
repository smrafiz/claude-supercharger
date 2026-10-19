# Clear Writing Mode (opt-in): Simplified Technical English, about 80%

Write prose the way ASD-STE100 (Simplified Technical English) writes maintenance
instructions, but only about 80% of the way: keep its structure and plain words,
not its full dictionary. This sets HOW you write. The economy tier still sets how
MUCH you write.

## Sentences
- One instruction in each sentence.
- Instructions: 20 words or fewer. Descriptions: 25 words or fewer.
- Use the active voice. Write instructions as commands: "Run the tests.", not
  "The tests should be run."
- Use simple tenses. Prefer "the hook blocks" to "the hook is blocking" or "has blocked".
- One topic in each paragraph, six sentences at most.

## Words
- Use one word for one thing, every time. If you call it a "guard", do not
  later call it a "check" or a "hook" unless it is a different thing.
- Prefer the simple word: start (not commence), use (not utilize), before (not
  prior to), make sure (not ensure), about (not approximately), to (not in order to).
- Do not leave out "the", "a" and "this" to save space in prose.
- Noun clusters of three words at most. Write "the timeout of the safety hook",
  not "safety hook timeout value setting".

## Structure
- Put steps in a numbered list, one action per step.
- Put a warning BEFORE the step it applies to, never after it:
  "WARNING: This deletes the branch. Run `git branch -D x`."
- Use a vertical list when a sentence would hold three or more items.

## What stays exact
Code, commands, file paths, identifiers, error text and quoted output are never
simplified. Technical names keep their real spelling, even when long.

## The other 20%
Do not force STE where it hurts: a code explanation may need a passive or an -ing
form to be correct. Correct and clear beats compliant.
