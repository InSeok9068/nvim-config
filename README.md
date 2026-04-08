# 💤 LazyVim

A starter template for [LazyVim](https://github.com/LazyVim/LazyVim).
Refer to the [documentation](https://lazyvim.github.io/installation) to get started.

### 관련 도구 설치

```shell
scoop bucket add extras
scoop install delta
scoop install ripgrep
scoop install fd
scoop install fzf
scoop install bat
```

### 터미널 폰트 다운로드

```shell
scoop bucket add nerd-fonts
scoop install JetBrainsMono-NF
```

### 한영키 자동화

```shell
scoop bucket add lewohy-bucket https://github.com/lewohy/lewohy-bucket
scoop install kren-select
```

### 윈도우 실시간 감지 nvim 제외

```shell
Add-MpPreference -ExclusionPath "$env:LOCALAPPDATA\nvim"
Add-MpPreference -ExclusionPath "$env:LOCALAPPDATA\nvim-data"
Add-MpPreference -ExclusionProcess "nvim.exe"
Add-MpPreference -ExclusionProcess "node.cmd"
```
