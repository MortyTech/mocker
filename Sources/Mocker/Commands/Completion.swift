import ArgumentParser

extension CompletionShell: @retroactive ExpressibleByArgument {}

/// `mocker completion bash|zsh|fish`, like `docker completion`. The script is generated from
/// the command tree, so it follows every subcommand and flag without being kept by hand.
struct Completion: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "completion",
        abstract: "Generate the autocompletion script for the specified shell"
    )

    @Argument(help: "The shell to generate a completion script for (bash, zsh or fish)")
    var shell: CompletionShell

    func run() {
        print(MockerCLI.completionScript(for: shell))
    }
}
