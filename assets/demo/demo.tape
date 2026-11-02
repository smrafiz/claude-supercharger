# Claude Supercharger — terminal demo
# Record:  brew install vhs && vhs assets/demo/demo.tape   (run from repo root)
# Produces: assets/demo/demo.gif
# Every verdict and message below is produced live by the hooks in this checkout;
# nothing is typed in by hand and no command is executed.

Output assets/demo/demo.gif

Require bash
Set Shell bash
Set FontSize 17
Set Width 1280
Set Height 580
Set Padding 24
Set Theme "Dracula"
Set TypingSpeed 45ms

Hide
Type "chmod +x assets/demo/*.sh && export TRY_CWD=$(./assets/demo/fixture.sh) && clear" Enter
Sleep 1500ms
Show

Type "# Claude asks to run a command. Supercharger decides first, outside the model." Sleep 600ms Enter
Enter Sleep 300ms

Type "./assets/demo/try.sh 'git status'" Sleep 300ms Enter Sleep 1200ms
Type "./assets/demo/try.sh 'rm -rf /'" Sleep 300ms Enter Sleep 1600ms
Type "./assets/demo/try.sh 'rm -rf src'" Sleep 300ms Enter Sleep 2600ms
Type "./assets/demo/try.sh 'git push --force origin main'" Sleep 300ms Enter Sleep 1600ms
Type "./assets/demo/try.sh 'cat ~/.aws/credentials'" Sleep 300ms Enter Sleep 1600ms
Type "./assets/demo/try.sh 'npm test'" Sleep 300ms Enter Sleep 1400ms

Enter
Type "# And the statusline: context, cache, cost, 5-hour and weekly usage." Sleep 600ms Enter
Type "./assets/demo/statusline.sh" Sleep 300ms Enter Sleep 3500ms
