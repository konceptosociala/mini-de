public errordomain CommandError {
    FAILED
}

/* Runs other programs. */
namespace Command {
    /* Output of the program; an error has its error output as the message. */
    public string run(string[] arguments) throws Error {
        var process = start(arguments, SubprocessFlags.NONE);
        string output, error_output;
        process.communicate_utf8(null, null, out output, out error_output);
        check(process, arguments, error_output);
        return output;
    }

    public async string run_async(string[] arguments, string? input = null) throws Error {
        var flags = input != null ? SubprocessFlags.STDIN_PIPE : SubprocessFlags.NONE;
        var process = start(arguments, flags);
        string output, error_output;
        yield process.communicate_utf8_async(input, null, out output, out error_output);
        check(process, arguments, error_output);
        return output;
    }

    Subprocess start(string[] arguments, SubprocessFlags flags) throws Error {
        var launcher = new SubprocessLauncher(
            flags | SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE
        );
        // programs are asked for output to be read by a program
        launcher.setenv("LC_ALL", "C.UTF-8", true);
        return launcher.spawnv(arguments);
    }

    void check(Subprocess process, string[] arguments, string error_output) throws CommandError {
        if (process.get_successful()) {
            return;
        }
        const int TIMED_OUT = 124;      // of the program timeout
        if (process.get_if_exited() && process.get_exit_status() == TIMED_OUT) {
            throw new CommandError.FAILED("Timed out");
        }
        string message = error_output.strip();
        throw new CommandError.FAILED(message != "" ? message : "%s failed".printf(arguments[0]));
    }
}
