/* Runs some work a little later, but never while a mouse button is pressed. */
class DeferredTask {
    const uint DRAG_POLL = 100;     // ms

    public delegate void Work();

    unowned X11.Connection connection;
    Work work;
    uint timer = 0;
    int64 due = 0;

    public DeferredTask(X11.Connection connection, owned Work work) {
        this.connection = connection;
        this.work = (owned) work;
    }

    /* In this time at most, however often it is asked for. */
    public void run_within(uint milliseconds) {
        if (timer == 0) {
            schedule(milliseconds);
        }
    }

    /* This long after it was asked for the last time. */
    public void run_after(uint milliseconds) {
        due = get_monotonic_time() + milliseconds * 1000;
        if (timer == 0) {
            schedule(milliseconds);
        }
    }

    void schedule(uint milliseconds) {
        timer = Timeout.add(milliseconds, () => {
            timer = 0;
            run_or_wait();
            return Source.REMOVE;
        });
    }

    void run_or_wait() {
        int64 left = (due - get_monotonic_time()) / 1000;
        if (left > 0) {
            schedule((uint) left);
        } else if (connection.pointer().any_button) {
            schedule(DRAG_POLL);
        } else {
            work();
        }
    }
}
