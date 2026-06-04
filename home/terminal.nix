# Interactive terminal environment shared by every host.
{
  pkgs,
  lib,
  ...
}:

let
  eza = "eza --group-directories-first";

  commonAliases = {
    ".." = "cd ..";
    "..." = "cd ../..";
    "...." = "cd ../../..";

    l = eza;
    la = "${eza} -a";
    ll = "${eza} -la";
    lt = "${eza} -la --sort=modified --reverse";

    rm = "rm -I";
    cp = "cp -i";
    mv = "mv -i";
    mkdir = "mkdir -pv";

    dps = "docker ps";
    dc = "docker compose";
    dcu = "docker compose up -d";
    dcd = "docker compose down";
    dcl = "docker compose logs -f";

    ni = "npm install";
    nrd = "npm run dev";
    nrb = "npm run build";
    nrt = "npm test";

    gs = "git status";
    please = "f";

    reload = "exec zsh";
  };
in
{
  home.packages = with pkgs; [
    docker-compose
    wl-clipboard
    xclip
    (writeShellScriptBin "victim" ''
      cat <<'EOF'
      victim: краткая памятка для жертв zsh vi-mode

      Модель в голове
        INSERT: обычный ввод. Backspace, Ctrl+W, Ctrl+A/E работают привычно.
        NORMAL: режим команд. Вы попали сюда через Esc. Чтобы снова печатать:
                нажмите i или a.

      Таблица перевода
        Обычная привычка        Vi-вариант              Что делает
        ---------------------------------------------------------------
        печатать текст          i / a                   снова вводить текст
        Home / Ctrl+A           0                       в начало строки
        End / Ctrl+E            $                       в конец строки
        Alt+B / Alt+F           b / w                   слово влево / вправо
        Backspace               X                       удалить символ слева
        Delete                  x                       удалить символ под курсором
        Ctrl+W                  db или Ctrl+W           удалить слово слева
        Ctrl+U                  d0 или Ctrl+U           удалить всё слева
        Ctrl+K                  D или Ctrl+K            удалить всё справа
        Ctrl+L                  Ctrl+L                  очистить экран
        Undo                    u                       отменить правку
        Редактор для команды    Esc, потом v            открыть строку в $EDITOR
        Я потерялся             i                       вернуться к вводу
        Я совсем потерялся      Ctrl+C                  отменить текущую строку

      Частые ловушки
        Backspace ничего не удаляет:
          Скорее всего, вы в NORMAL. Нажмите i или используйте x/X.
          В этом конфиге Backspace дополнительно привязан и в NORMAL.

        Ctrl+W ведёт себя странно:
          В чистом vi NORMAL удаление слова — это db/dw. В этом конфиге
          Ctrl+W тоже работает в NORMAL, чтобы мышечная память не страдала.

        Буквы не печатаются, а делают какую-то магию:
          Вы в NORMAL. Нажмите i, чтобы вводить перед курсором, или a,
          чтобы вводить после курсора.

        Подсказка по курсору:
          Тонкий курсор = INSERT. Блочный курсор = NORMAL, если терминал
          поддерживает смену формы курсора.
      EOF
    '')
  ];

  # ── Starship prompt (bash + zsh) ─────────────────────────────
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      # /mnt/c (drvfs) in WSL can make git status slower than Starship's default timeout.
      command_timeout = 5000;
      username = {
        style_user = "blue bold";
        style_root = "red bold";
        format = "[$user]($style) ";
        show_always = true;
      };
      hostname = {
        ssh_only = false;
        ssh_symbol = "🌐 ";
        format = "on [$hostname](bold red) ";
        trim_at = ".local";
      };
      directory.truncation_length = 4;
      git_branch.format = "on [$symbol$branch]($style) ";
      git_status.disabled = false;
    };
  };

  # ── fzf  (Ctrl-R / Ctrl-T / Alt-C) ──────────────────────────
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    defaultCommand = "fd --type f";
    fileWidgetCommand = "fd --type f";
    changeDirWidgetCommand = "fd --type d";
    changeDirWidgetOptions = [ "--preview 'tree -C {} | head -200'" ];
    defaultOptions = [
      "--height=40%"
      "--layout=reverse"
      "--border"
      "--info=inline"
    ];
    fileWidgetOptions = [
      "--preview 'bat --style=numbers --color=always --line-range=:200 {} 2>/dev/null'"
    ];
    historyWidgetOptions = [
      "--sort"
      "--exact"
    ];
    tmux = {
      enableShellIntegration = true;
      shellIntegrationOptions = [
        "-p"
        "80%,70%"
      ];
    };
  };

  # ── zoxide  (z <pattern>) ───────────────────────────────────
  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  # ── direnv + nix-direnv ──────────────────────────────────────
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  # ── atuin  (smart history search) ────────────────────────────
  programs.atuin = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    settings = {
      auto_sync = false;
      filter_mode = "host";
    };
  };

  programs.pay-respects = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  programs.tmux = {
    enable = true;
    baseIndex = 1;
    clock24 = true;
    escapeTime = 0;
    historyLimit = 50000;
    keyMode = "vi";
    mouse = true;
    sensibleOnTop = true;
    terminal = "screen-256color";
    plugins = with pkgs.tmuxPlugins; [
      yank
    ];
    extraConfig = ''
      set -g renumber-windows on
      set -g detach-on-destroy off
      setw -g automatic-rename on

      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind c new-window -c "#{pane_current_path}"
      bind r source-file ~/.config/tmux/tmux.conf \; display-message "tmux config reloaded"
    '';
  };

  # ── Zsh ──────────────────────────────────────────────────────
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    defaultKeymap = "viins";
    shellAliases = commonAliases;
    history = {
      size = 50000;
      save = 100000;
      append = true;
      extended = true;
      ignoreAllDups = true;
      saveNoDups = true;
      findNoDups = true;
      expireDuplicatesFirst = true;
      ignorePatterns = [
        "rm *"
        "pkill *"
        "kill *"
      ];
    };
    historySubstringSearch = {
      enable = true;
      searchUpKey = [
        "^[[A"
      ];
      searchDownKey = [
        "^[[B"
      ];
    };
    setOptions = [
      "AUTO_PUSHD"
      "PUSHD_IGNORE_DUPS"
      "INTERACTIVE_COMMENTS"
      "COMPLETE_IN_WORD"
    ];
    initContent = lib.mkOrder 1050 ''
      KEYTIMEOUT=10

      autoload -Uz edit-command-line
      zle -N edit-command-line

      for keymap in viins vicmd; do
        bindkey -M "$keymap" '^?' backward-delete-char
        bindkey -M "$keymap" '^H' backward-delete-char
        bindkey -M "$keymap" '^a' beginning-of-line
        bindkey -M "$keymap" '^e' end-of-line
        bindkey -M "$keymap" '^w' backward-kill-word
        bindkey -M "$keymap" '^u' backward-kill-line
        bindkey -M "$keymap" '^k' kill-line
        bindkey -M "$keymap" '^l' clear-screen
        bindkey -M "$keymap" '^[f' forward-word
        bindkey -M "$keymap" '^[b' backward-word
      done
      unset keymap

      bindkey -M viins '^f' autosuggest-accept
      bindkey -M vicmd 'v' edit-command-line
      [[ -n "$terminfo[kcuu1]" ]] && bindkey "$terminfo[kcuu1]" history-substring-search-up
      [[ -n "$terminfo[kcud1]" ]] && bindkey "$terminfo[kcud1]" history-substring-search-down

      zle-keymap-select() {
        case "$KEYMAP" in
          vicmd) print -n -- $'\e[2 q' ;;
          *) print -n -- $'\e[6 q' ;;
        esac
      }
      zle-line-init() { zle-keymap-select }
      zle-line-finish() { print -n -- $'\e[0 q' }
      zle -N zle-keymap-select
      zle -N zle-line-init
      zle -N zle-line-finish

      zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
      zstyle ':completion:*' menu select

      alias -- -='cd -'

      cl() {
        builtin cd "''${1:-$HOME}" && eza -la --group-directories-first
      }

      mkcd() {
        [[ $# -eq 1 ]] || { print -u2 "usage: mkcd <dir>"; return 2; }
        mkdir -p "$1" && builtin cd "$1"
      }

      copy() {
        if [[ $# -gt 0 ]]; then
          printf "%s" "$*" | copy
          return
        fi

        if [[ -n "$WAYLAND_DISPLAY" ]] && command -v wl-copy >/dev/null 2>&1; then
          wl-copy
        elif [[ -n "$DISPLAY" ]] && command -v xclip >/dev/null 2>&1; then
          xclip -selection clipboard
        elif command -v clip.exe >/dev/null 2>&1; then
          clip.exe
        else
          print -u2 "copy: no clipboard provider found"
          return 1
        fi
      }

      cpath() {
        printf "%s" "$PWD" | copy
      }

      fco() {
        git rev-parse --git-dir >/dev/null 2>&1 || return
        local branch
        branch=$(
          git for-each-ref --format='%(refname:short)' refs/heads refs/remotes |
            command grep -v '/HEAD$' |
            sed 's#^origin/##' |
            sort -u |
            fzf --prompt='git checkout> '
        ) || return
        [[ -n "$branch" ]] && git checkout "$branch"
      }

      fkill() {
        local pid
        pid=$(
          ps -u "$USER" -o pid=,comm=,args= |
            fzf --prompt='kill> ' |
            awk '{print $1}'
        ) || return
        [[ -n "$pid" ]] && kill "$pid"
      }
    '';

    plugins = [
      {
        name = "zsh-shortcut-git";
        src = pkgs.fetchFromGitHub {
          owner = "zh30";
          repo  = "zsh-shortcut-git";
          rev   = "f1d0d6f929d72749c7aa3535a98949bec5e516af";
          hash  = "sha256-LP5StJwATK4L0GqnL97ATfSNQYe54+E/9ursS8KRiJ8=";
        };
        file = "zsh-shortcut-git.plugin.zsh";
      }
    ];
  };
}
