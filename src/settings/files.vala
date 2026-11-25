namespace Files {
    public string read(string path) throws FileError {
        string text;
        FileUtils.get_contents(path, out text);
        return text;
    }

    /* Replaces a file at once, so that a failure never leaves half of it. Links are followed. */
    public void replace(string path, string text) throws FileError {
        string? resolved = Posix.realpath(path);
        string target = resolved != null ? resolved : path;
        Posix.Stat status;
        int mode = Posix.stat(target, out status) == 0 ? (int) (status.st_mode & 0777) : 0644;
        FileUtils.set_contents_full(target, text, -1, FileSetContentsFlags.CONSISTENT, mode);
    }
}
