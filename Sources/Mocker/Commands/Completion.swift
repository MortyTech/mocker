import ArgumentParser

// MARK: - mocker completion <shell>
//
// Docker-parity completion command. `docker completion bash|zsh|fish` prints a
// completion script; this does the same for mocker, plus dynamic completion of
// container names, image references, volumes and networks by shelling out to
// mocker itself (the same technique Docker's own completion scripts use).
//
// The scripts are self-contained; no ArgumentParser internals are used, so this
// keeps working regardless of the custom main() entry point in MockerCLI.swift.

struct Completion: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "completion",
        abstract: "Generate the autocompletion script for the specified shell",
        discussion: """
        Output shell completion code for the specified shell (bash, zsh or fish).
        The shell code must then be evaluated to provide interactive completion.

        macOS (zsh):
          mkdir -p ~/.zsh/completions
          mocker completion zsh > ~/.zsh/completions/_mocker
          echo 'fpath=(~/.zsh/completions $fpath)' >> ~/.zshrc
          echo 'autoload -Uz compinit && compinit' >> ~/.zshrc

        bash (Homebrew):
          mkdir -p $(brew --prefix)/etc/bash_completion.d
          mocker completion bash > $(brew --prefix)/etc/bash_completion.d/mocker

        bash (user-local):
          mkdir -p ~/.local/share/bash-completion/completions
          mocker completion bash > ~/.local/share/bash-completion/completions/mocker

        fish:
          mkdir -p ~/.config/fish/completions
          mocker completion fish > ~/.config/fish/completions/mocker.fish
        """
    )

    enum Shell: String, ExpressibleByArgument, CaseIterable {
        case bash
        case zsh
        case fish
    }

    @Argument(help: "The shell to generate a completion script for")
    var shell: Shell

    func run() throws {
        switch shell {
        case .bash:
            print(MockerCompletions.bash)
        case .zsh:
            print(MockerCompletions.zsh)
        case .fish:
            print(MockerCompletions.fish)
        }
    }
}

// MARK: - Embedded completion scripts

enum MockerCompletions {
    static let bash = """
    # bash completion for mocker
    #
    # Install:
    #   mocker completion bash > $(brew --prefix)/etc/bash_completion.d/mocker   (brew)
    #   mocker completion bash > ~/.local/share/bash-completion/completions/mocker (user)

    __mocker_complete_containers() {
        COMPREPLY+=( $(compgen -W "$(mocker ps -a --format '{{.Names}}' 2>/dev/null)" -- "$cur") )
    }

    __mocker_complete_running_containers() {
        COMPREPLY+=( $(compgen -W "$(mocker ps --format '{{.Names}}' 2>/dev/null)" -- "$cur") )
    }

    __mocker_complete_stopped_containers() {
        local running stopped
        running=$(mocker ps --format '{{.Names}}' 2>/dev/null | sort)
        stopped=$(mocker ps -a --format '{{.Names}}' 2>/dev/null | sort)
        COMPREPLY+=( $(compgen -W "$(comm -13 <(printf '%s\\n' "$running") <(printf '%s\\n' "$stopped"))" -- "$cur") )
    }

    __mocker_complete_images() {
        COMPREPLY+=( $(compgen -W "$(mocker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null)" -- "$cur") )
    }

    __mocker_complete_volumes() {
        COMPREPLY+=( $(compgen -W "$(mocker volume ls -q 2>/dev/null)" -- "$cur") )
    }

    __mocker_complete_networks() {
        COMPREPLY+=( $(compgen -W "$(mocker network ls --format '{{.Name}}' 2>/dev/null)" -- "$cur") )
    }

    __mocker_complete_files() {
        COMPREPLY+=( $(compgen -f -- "$cur") )
    }

    _mocker() {
        local cur prev
        if declare -F _init_completion >/dev/null 2>&1; then
            _init_completion || return
        else
            cur="${COMP_WORDS[COMP_CWORD]}"
            prev="${COMP_WORDS[COMP_CWORD-1]}"
        fi

        local commands="run create start ps stop restart kill wait rm exec logs build pull push images tag rmi inspect stats login logout version cp attach rename port top diff pause unpause update history save load export commit import search container image manifest network volume compose system proxy serve"

        # Find the active subcommand (first non-option word after the program name).
        local i command=""
        for (( i=1; i < COMP_CWORD; i++ )); do
            case "${COMP_WORDS[i]}" in
                -*) ;;
                *) command="${COMP_WORDS[i]}"; break ;;
            esac
        done

        # Complete a subcommand name.
        if [[ -z "$command" ]]; then
            case "$prev" in
                completion) COMPREPLY+=( $(compgen -W "bash zsh fish" -- "$cur") ); return ;;
            esac
            COMPREPLY+=( $(compgen -W "$commands completion" -- "$cur") )
            return
        fi

        case "$command" in
            run|create)
                case "$prev" in
                    --network|--net) __mocker_complete_networks; return ;;
                    --env-file) __mocker_complete_files; return ;;
                    --platform) COMPREPLY+=( $(compgen -W "linux/amd64 linux/arm64" -- "$cur") ); return ;;
                esac
                COMPREPLY+=( $(compgen -W "-d -p -e -v --name --rm -it --network --env-file -w --entrypoint --platform --restart --pull --memory --cpus" -- "$cur") )
                [[ "$cur" == -* ]] || __mocker_complete_images
                ;;
            start)
                COMPREPLY+=( $(compgen -W "-a -i" -- "$cur") )
                [[ "$cur" == -* ]] || __mocker_complete_stopped_containers
                ;;
            stop|restart|kill|pause|unpause|wait|rename|update)
                COMPREPLY+=( $(compgen -W "--help" -- "$cur") )
                [[ "$cur" == -* ]] || __mocker_complete_running_containers
                ;;
            logs)
                COMPREPLY+=( $(compgen -W "-f --follow --tail -t --timestamps --details --since --until --help" -- "$cur") )
                [[ "$cur" == -* ]] || __mocker_complete_running_containers
                ;;
            exec)
                case "$prev" in
                    -e|--env) return ;;
                    -w|--workdir) __mocker_complete_files; return ;;
                    -u|--user) return ;;
                esac
                COMPREPLY+=( $(compgen -W "-d -i -t -e --env -w --workdir -u --user --detach --privileged --help" -- "$cur") )
                [[ "$cur" == -* ]] || __mocker_complete_running_containers
                ;;
            attach|port|top|diff|commit|export)
                case "$command:$prev" in
                    export:-o|export:--output) __mocker_complete_files; return ;;
                esac
                COMPREPLY+=( $(compgen -W "--help" -- "$cur") )
                [[ "$cur" == -* ]] || __mocker_complete_running_containers
                ;;
            rm)
                COMPREPLY+=( $(compgen -W "-f -v --force --volumes --link --help" -- "$cur") )
                [[ "$cur" == -* ]] || __mocker_complete_containers
                ;;
            ps)
                COMPREPLY+=( $(compgen -W "-a -q --all --quiet --format --filter -n -l --latest --size --no-trunc --help" -- "$cur") )
                ;;
            images)
                COMPREPLY+=( $(compgen -W "-a -q --all --quiet --digests --format --filter --no-trunc --tree --help" -- "$cur") )
                ;;
            rmi)
                COMPREPLY+=( $(compgen -W "-f --force --help" -- "$cur") )
                [[ "$cur" == -* ]] || __mocker_complete_images
                ;;
            tag|history)
                COMPREPLY+=( $(compgen -W "--format -q --quiet --no-trunc --help" -- "$cur") )
                [[ "$cur" == -* ]] || __mocker_complete_images
                ;;
            pull|push|search|login|logout|load)
                COMPREPLY+=( $(compgen -W "-a --all-tags --platform --quiet --help" -- "$cur") )
                ;;
            build)
                case "$prev" in
                    --platform) COMPREPLY+=( $(compgen -W "linux/amd64 linux/arm64" -- "$cur") ); return ;;
                    --builder|-f|--file) __mocker_complete_files; return ;;
                esac
                COMPREPLY+=( $(compgen -W "-t -f --tag --file --platform --no-cache --pull --builder --target --build-arg --help" -- "$cur") )
                [[ "$cur" == -* ]] || __mocker_complete_files
                ;;
            save|import)
                case "$prev" in
                    -o|--output) __mocker_complete_files; return ;;
                esac
                COMPREPLY+=( $(compgen -W "-o --output --help" -- "$cur") )
                [[ "$cur" == -* ]] || __mocker_complete_images
                ;;
            inspect)
                COMPREPLY+=( $(compgen -W "-f --format --type --size --help" -- "$cur") )
                [[ "$cur" == -* ]] || { __mocker_complete_containers; __mocker_complete_images; __mocker_complete_volumes; __mocker_complete_networks; }
                ;;
            stats)
                COMPREPLY+=( $(compgen -W "--all --no-stream --format --no-trunc --help" -- "$cur") )
                ;;
            cp)
                [[ "$cur" == -* ]] || __mocker_complete_containers
                ;;
            manifest)
                COMPREPLY+=( $(compgen -W "inspect create add rm annotate push" -- "$cur") )
                ;;
            compose)
                COMPREPLY+=( $(compgen -W "-f --file up down ps logs restart stop start kill rm build pull exec run config" -- "$cur") )
                ;;
            system)
                COMPREPLY+=( $(compgen -W "info prune events df" -- "$cur") )
                ;;
            container)
                COMPREPLY+=( $(compgen -W "ls run inspect exec logs rm prune start stop" -- "$cur") )
                ;;
            image)
                COMPREPLY+=( $(compgen -W "ls inspect tag rm push pull history prune build" -- "$cur") )
                ;;
            network)
                COMPREPLY+=( $(compgen -W "create ls rm inspect connect disconnect prune" -- "$cur") )
                ;;
        esac
    }

    complete -o default -F _mocker mocker
    """

    static let zsh = """
    #compdef mocker
    #
    # zsh completion for mocker
    #
    # Install:
    #   mkdir -p ~/.zsh/completions
    #   mocker completion zsh > ~/.zsh/completions/_mocker
    #   fpath=(~/.zsh/completions $fpath)
    #   autoload -Uz compinit && compinit

    _mocker_containers() {
      local -a containers
      containers=(${(f)"$(mocker ps -a --format '{{.Names}}' 2>/dev/null)"})
      _describe -t containers 'containers' containers -S '' -- "$@"
    }

    _mocker_stopped_containers() {
      local -a running all stopped
      running=(${(f)"$(mocker ps --format '{{.Names}}' 2>/dev/null)"})
      all=(${(f)"$(mocker ps -a --format '{{.Names}}' 2>/dev/null)"})
      stopped=(${all:|running})
      _describe -t stopped-containers 'stopped containers' stopped -S '' -- "$@"
    }

    _mocker_running_containers() {
      local -a containers
      containers=(${(f)"$(mocker ps --format '{{.Names}}' 2>/dev/null)"})
      _describe -t running-containers 'running containers' containers -S '' -- "$@"
    }

    _mocker_images() {
      local -a images
      images=(${(f)"$(mocker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null)"})
      _describe -t images 'images' images -S '' -- "$@"
    }

    _mocker_volumes() {
      local -a volumes
      volumes=(${(f)"$(mocker volume ls -q 2>/dev/null)"})
      _describe -t volumes 'volumes' volumes -S '' -- "$@"
    }

    _mocker_networks() {
      local -a networks
      networks=(${(f)"$(mocker network ls --format '{{.Name}}' 2>/dev/null)"})
      _describe -t networks 'networks' networks -S '' -- "$@"
    }

    _mocker() {
      local -a commands
      commands=(
        'run:Run a command in a new container'
        'create:Create a new container'
        'start:Start one or more stopped containers'
        'ps:List containers'
        'stop:Stop one or more running containers'
        'restart:Restart one or more containers'
        'kill:Kill one or more running containers'
        'wait:Block until one or more containers stop'
        'rm:Remove one or more containers'
        'exec:Run a command in a running container'
        'logs:Fetch the logs of a container'
        'build:Build an image from a Dockerfile'
        'pull:Download an image from a registry'
        'push:Upload an image to a registry'
        'images:List images'
        'tag:Create a tag that refers to an image'
        'rmi:Remove one or more images'
        'inspect:Return low-level information on objects'
        'stats:Display a live stream of container resource usage'
        'login:Log in to a registry'
        'logout:Log out from a registry'
        'version:Show version information'
        'cp:Copy files between a container and the filesystem'
        'attach:Attach to a running container'
        'rename:Rename a container'
        'port:List port mappings for the container'
        'top:Display the running processes of a container'
        'diff:Inspect changes to files or directories on a container'
        'pause:Pause all processes within one or more containers'
        'unpause:Unpause all processes within one or more containers'
        'update:Update configuration of one or more containers'
        'history:Show the history of an image'
        'save:Save one or more images to a tar archive'
        'load:Load an image from a tar archive'
        'export:Export a container filesystem as a tar archive'
        'commit:Create a new image from a container changes'
        'import:Import the contents from a tarball to create an image'
        'search:Search for images on a registry'
        'container:Manage containers'
        'image:Manage images'
        'manifest:Manage image manifests and manifest lists'
        'network:Manage networks'
        'volume:Manage volumes'
        'compose:Compose multi-container applications'
        'system:Manage mocker system'
        'proxy:Manage the port proxy'
        'serve:Run a Docker Engine API-compatible daemon'
        'completion:Generate shell completion scripts'
      )

      _arguments -C \\
        '(- : *)--help[Show help]' \\
        '1:command:->command' \\
        '*::arg:->args'

      case $state in
        (command)
          _describe -t mocker-commands 'mocker command' commands
          ;;
        (args)
          case $words[1] in
            (run|create)
              _arguments \\
                '(-d)--detach[Run container in background]' \\
                '--name=[Assign a name to the container]:name:' \\
                '(-p)--publish=[Publish a port]:port:' \\
                '(-e)--env=[Set an environment variable]:env:' \\
                '--env-file=[Read env from a file]:file:_files' \\
                '(-v)--volume=[Bind mount a volume]:volume:' \\
                '--network=[Connect to a network]:network:_mocker_networks' \\
                '--platform=[Set platform]:platform:(linux/amd64 linux/arm64)' \\
                '--entrypoint=[Overwrite the entrypoint]:entrypoint:' \\
                '(-w)--workdir=[Working directory]:dir:_files -/' \\
                '--rm[Remove container on exit]' \\
                '(-i)--interactive[Keep STDIN open]' \\
                '(-t)--tty[Allocate a TTY]' \\
                '*:image:_mocker_images'
              ;;
            (exec|logs|attach|port|top|wait|kill|pause|unpause|stop|restart|rename|update|commit|diff|export)
              _arguments '*:running container:_mocker_running_containers'
              ;;
            (start)
              _arguments '*:stopped container:_mocker_stopped_containers'
              ;;
            (rm)
              _arguments \\
                '(-f)--force[Force removal]' \\
                '(-v)--volumes[Remove anonymous volumes]' \\
                '*:container:_mocker_containers'
              ;;
            (images)
              _arguments \\
                '(-a)--all[Show all images]' \\
                '(-q)--quiet[Only show IDs]' \\
                '--digests[Show digests]' \\
                '--format=[Format output]:template:' \\
                '*: :'
              ;;
            (rmi)
              _arguments \\
                '(-f)--force[Force removal]' \\
                '*:image:_mocker_images'
              ;;
            (tag|history|push|save|manifest)
              _arguments '*:image:_mocker_images'
              ;;
            (build)
              _arguments \\
                '(-t)--tag=[Name and tag]:tag:' \\
                '(-f)--file=[Dockerfile]:file:_files' \\
                '--platform=[Target platform]:platform:(linux/amd64 linux/arm64)' \\
                '--builder=[BuildKit node]:builder:' \\
                '--no-cache[Do not use cache]' \\
                '*:path:_files -/'
              ;;
            (pull|login|logout|search|load|import)
              _arguments '*: :'
              ;;
            (inspect)
              _arguments \\
                '(-f)--format=[Format with Go template]:template:' \\
                '--type=[Constrain discovery]:type:(container image network volume)' \\
                '*:object:_mocker_containers'
              ;;
            (cp)
              _arguments '*:container:_mocker_containers'
              ;;
            (volume)
              local -a sub
              sub=('create:Create a volume' 'ls:List volumes' 'rm:Remove volumes' 'inspect:Inspect a volume' 'prune:Remove unused volumes')
              if (( CURRENT == 2 )); then
                _describe -t volume-commands 'volume command' sub
              else
                case $words[2] in
                  (rm|inspect)
                    _arguments '*:volume:_mocker_volumes'
                    ;;
                  (*)
                    _arguments '*: :'
                    ;;
                esac
              fi
              ;;
            (network)
              local -a sub
              sub=('create:Create a network' 'ls:List networks' 'rm:Remove networks' 'inspect:Inspect a network' 'connect:Connect a container' 'disconnect:Disconnect a container' 'prune:Remove unused networks')
              if (( CURRENT == 2 )); then
                _describe -t network-commands 'network command' sub
              else
                case $words[2] in
                  (rm|inspect|connect|disconnect)
                    _arguments '*:network:_mocker_networks'
                    ;;
                  (*)
                    _arguments '*: :'
                    ;;
                esac
              fi
              ;;
            (compose)
              _arguments \\
                '(-f)--file=[Compose file]:file:_files' \\
                '1:command:(up down ps logs restart stop start kill rm build pull exec run config)' \\
                '*: :'
              ;;
            (system)
              _arguments '1:command:(info prune events df)'
              ;;
            (container)
              _arguments '1:command:(ls run inspect exec logs rm prune start stop)'
              ;;
            (image)
              _arguments '1:command:(ls inspect tag rm push pull history prune build)'
              ;;
            (completion)
              _arguments '1:shell:(bash zsh fish)'
              ;;
            (*)
              _arguments '*: :'
              ;;
          esac
          ;;
      esac
    }

    compdef _mocker mocker
    """

    static let fish = """
    # fish completion for mocker
    #
    # Install:
    #   mocker completion fish > ~/.config/fish/completions/mocker.fish

    function __mocker_containers
        mocker ps -a --format '{{.Names}}' 2>/dev/null
    end

    function __mocker_running_containers
        mocker ps --format '{{.Names}}' 2>/dev/null
    end

    function __mocker_images
        mocker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null
    end

    function __mocker_volumes
        mocker volume ls -q 2>/dev/null
    end

    function __mocker_networks
        mocker network ls --format '{{.Name}}' 2>/dev/null
    end

    complete -c mocker -f

    complete -c mocker -n '__fish_use_subcommand' -l help -d 'Show help'

    complete -c mocker -n '__fish_use_subcommand' -a run -d 'Run a command in a new container'
    complete -c mocker -n '__fish_use_subcommand' -a create -d 'Create a new container'
    complete -c mocker -n '__fish_use_subcommand' -a start -d 'Start stopped containers'
    complete -c mocker -n '__fish_use_subcommand' -a ps -d 'List containers'
    complete -c mocker -n '__fish_use_subcommand' -a stop -d 'Stop running containers'
    complete -c mocker -n '__fish_use_subcommand' -a restart -d 'Restart containers'
    complete -c mocker -n '__fish_use_subcommand' -a kill -d 'Kill containers'
    complete -c mocker -n '__fish_use_subcommand' -a wait -d 'Block until containers stop'
    complete -c mocker -n '__fish_use_subcommand' -a rm -d 'Remove containers'
    complete -c mocker -n '__fish_use_subcommand' -a exec -d 'Run a command in a running container'
    complete -c mocker -n '__fish_use_subcommand' -a logs -d 'Fetch container logs'
    complete -c mocker -n '__fish_use_subcommand' -a build -d 'Build an image from a Dockerfile'
    complete -c mocker -n '__fish_use_subcommand' -a pull -d 'Download an image'
    complete -c mocker -n '__fish_use_subcommand' -a push -d 'Upload an image'
    complete -c mocker -n '__fish_use_subcommand' -a images -d 'List images'
    complete -c mocker -n '__fish_use_subcommand' -a tag -d 'Create an image tag'
    complete -c mocker -n '__fish_use_subcommand' -a rmi -d 'Remove images'
    complete -c mocker -n '__fish_use_subcommand' -a inspect -d 'Inspect objects'
    complete -c mocker -n '__fish_use_subcommand' -a stats -d 'Container resource usage'
    complete -c mocker -n '__fish_use_subcommand' -a login -d 'Log in to a registry'
    complete -c mocker -n '__fish_use_subcommand' -a logout -d 'Log out from a registry'
    complete -c mocker -n '__fish_use_subcommand' -a version -d 'Show version'
    complete -c mocker -n '__fish_use_subcommand' -a cp -d 'Copy files to/from a container'
    complete -c mocker -n '__fish_use_subcommand' -a attach -d 'Attach to a running container'
    complete -c mocker -n '__fish_use_subcommand' -a rename -d 'Rename a container'
    complete -c mocker -n '__fish_use_subcommand' -a port -d 'List port mappings'
    complete -c mocker -n '__fish_use_subcommand' -a top -d 'Container processes'
    complete -c mocker -n '__fish_use_subcommand' -a diff -d 'Container filesystem changes'
    complete -c mocker -n '__fish_use_subcommand' -a pause -d 'Pause containers'
    complete -c mocker -n '__fish_use_subcommand' -a unpause -d 'Unpause containers'
    complete -c mocker -n '__fish_use_subcommand' -a update -d 'Update container config'
    complete -c mocker -n '__fish_use_subcommand' -a history -d 'Image history'
    complete -c mocker -n '__fish_use_subcommand' -a save -d 'Save images to a tar archive'
    complete -c mocker -n '__fish_use_subcommand' -a load -d 'Load an image from a tar archive'
    complete -c mocker -n '__fish_use_subcommand' -a export -d 'Export a container filesystem'
    complete -c mocker -n '__fish_use_subcommand' -a commit -d 'Create an image from a container'
    complete -c mocker -n '__fish_use_subcommand' -a import -d 'Import a tarball as an image'
    complete -c mocker -n '__fish_use_subcommand' -a search -d 'Search a registry'
    complete -c mocker -n '__fish_use_subcommand' -a container -d 'Manage containers'
    complete -c mocker -n '__fish_use_subcommand' -a image -d 'Manage images'
    complete -c mocker -n '__fish_use_subcommand' -a manifest -d 'Manage manifests'
    complete -c mocker -n '__fish_use_subcommand' -a network -d 'Manage networks'
    complete -c mocker -n '__fish_use_subcommand' -a volume -d 'Manage volumes'
    complete -c mocker -n '__fish_use_subcommand' -a compose -d 'Compose applications'
    complete -c mocker -n '__fish_use_subcommand' -a system -d 'Manage mocker system'
    complete -c mocker -n '__fish_use_subcommand' -a completion -d 'Generate shell completions'

    complete -c mocker -n '__fish_seen_subcommand_from completion' -a 'bash zsh fish' -d 'Shell'

    # run / create
    complete -c mocker -n '__fish_seen_subcommand_from run create' -s d -l detach -d 'Run in background'
    complete -c mocker -n '__fish_seen_subcommand_from run create' -l name -d 'Container name'
    complete -c mocker -n '__fish_seen_subcommand_from run create' -s p -l publish -d 'Publish a port'
    complete -c mocker -n '__fish_seen_subcommand_from run create' -s e -l env -d 'Environment variable'
    complete -c mocker -n '__fish_seen_subcommand_from run create' -l env-file -r -d 'Env file'
    complete -c mocker -n '__fish_seen_subcommand_from run create' -s v -l volume -d 'Bind mount'
    complete -c mocker -n '__fish_seen_subcommand_from run create' -l network -xa '(__mocker_networks)' -d 'Network'
    complete -c mocker -n '__fish_seen_subcommand_from run create' -l platform -xa 'linux/amd64 linux/arm64' -d 'Platform'
    complete -c mocker -n '__fish_seen_subcommand_from run create' -l rm -d 'Remove on exit'
    complete -c mocker -n '__fish_seen_subcommand_from run create' -s i -l interactive -d 'Keep STDIN open'
    complete -c mocker -n '__fish_seen_subcommand_from run create' -s t -l tty -d 'Allocate a TTY'
    complete -c mocker -n '__fish_seen_subcommand_from run create' -fa '(__mocker_images)'

    # Lifecycle / attach commands take running container names
    complete -c mocker -n '__fish_seen_subcommand_from exec logs attach port top wait kill pause unpause stop restart rename update commit diff export stats' -fa '(__mocker_running_containers)'
    complete -c mocker -n '__fish_seen_subcommand_from start' -fa '(__mocker_containers)'
    complete -c mocker -n '__fish_seen_subcommand_from rm; and not __fish_seen_subcommand_from compose' -fa '(__mocker_containers)'

    # Image commands
    complete -c mocker -n '__fish_seen_subcommand_from rmi tag history push save' -fa '(__mocker_images)'
    complete -c mocker -n '__fish_seen_subcommand_from images' -s q -l quiet -d 'Only show IDs'
    complete -c mocker -n '__fish_seen_subcommand_from images' -s a -l all -d 'Show all images'
    complete -c mocker -n '__fish_seen_subcommand_from images' -l digests -d 'Show digests'
    complete -c mocker -n '__fish_seen_subcommand_from images' -l format -d 'Format template'

    # ps
    complete -c mocker -n '__fish_seen_subcommand_from ps; and not __fish_seen_subcommand_from compose' -s a -l all -d 'Show all containers'
    complete -c mocker -n '__fish_seen_subcommand_from ps; and not __fish_seen_subcommand_from compose' -s q -l quiet -d 'Only show IDs'
    complete -c mocker -n '__fish_seen_subcommand_from ps; and not __fish_seen_subcommand_from compose' -l format -d 'Format template'

    # build
    complete -c mocker -n '__fish_seen_subcommand_from build' -s t -l tag -d 'Name and tag'
    complete -c mocker -n '__fish_seen_subcommand_from build' -s f -l file -r -d 'Dockerfile'
    complete -c mocker -n '__fish_seen_subcommand_from build' -l platform -xa 'linux/amd64 linux/arm64' -d 'Platform'
    complete -c mocker -n '__fish_seen_subcommand_from build' -l no-cache -d 'Do not use cache'

    # inspect
    complete -c mocker -n '__fish_seen_subcommand_from inspect' -s f -l format -d 'Go template'
    complete -c mocker -n '__fish_seen_subcommand_from inspect' -fa '(__mocker_containers; __mocker_images; __mocker_volumes; __mocker_networks)'

    # volume
    complete -c mocker -n '__fish_seen_subcommand_from volume' -a 'create ls rm inspect prune'
    complete -c mocker -n '__fish_seen_subcommand_from volume' -fa '(__mocker_volumes)'

    # network
    complete -c mocker -n '__fish_seen_subcommand_from network' -a 'create ls rm inspect connect disconnect prune'
    complete -c mocker -n '__fish_seen_subcommand_from network' -fa '(__mocker_networks)'
    """
}
