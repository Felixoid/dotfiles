My dotfiles. It uses [rcm](https://github.com/thoughtbot/rcm). For get it work just run
```
git clone $(repolink) ~/.dotfiles
rcup -f -v rcrc && rcup -fv # first for update rcrc only, second for proper installation
```

## standalone_rcup.sh

This file is created via:

`rcup -fvg | sed "s:$PWD:\${PWD}:; s:$HOME:\${HOME}:" > standalone_rcup.sh`

The easiest way to use is:

`curl https://github.com/Felixoid/dotfiles/archive/master.tar.gz -L | tar xz && cd dotfiles-master && bash standalone_rcup.sh && cd -`
