My dotfiles. It uses [rcm](https://github.com/thoughtbot/rcm). For get it work just run
```
git clone $(repolink) ~/.dotfiles
rcup -f -v -x README.md && rcup -fv # first for update rcrc, second for proper installation
```

## standalone_rcup.sh

This file is created via:

`rcup -fvg | sed "s:${PWD}:\$PWD:; s:$HOME:\$HOME:" > standalone_rcup.sh`
