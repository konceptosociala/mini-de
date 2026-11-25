namespace SingleInstance {
    /* False if this program already runs on the display. The lock lasts as long as the process. */
    public bool acquire(string program) {
        string display = Environment.get_variable("DISPLAY") ?? "";
        string file_name = "%s%s.lock".printf(program, display.replace("/", "_"));
        string path = Path.build_filename(Environment.get_user_runtime_dir(), file_name);
        int file = Posix.open(path, Posix.O_RDWR | Posix.O_CREAT | Posix.O_CLOEXEC, 0600);
        if (file < 0) {
            return true;
        }
        return FileLock.flock(file, FileLock.EXCLUSIVE | FileLock.NON_BLOCKING) == 0;
    }
}
