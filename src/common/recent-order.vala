/* Numbers in most recently used order. */
public class RecentOrder {
    ulong[] items = {};

    public int length {
        get { return items.length; }
    }

    public new ulong get(int index) {
        return items[index];
    }

    public int index_of(ulong item) {
        for (int index = 0; index < items.length; index++) {
            if (items[index] == item) {
                return index;
            }
        }
        return -1;
    }

    /* Adds an item as the least recently used one, unless it is there already. */
    public void append(ulong item) {
        if (index_of(item) < 0) {
            items += item;
        }
    }

    /* Does nothing for an unknown item. */
    public void move_to_front(ulong item) {
        int index = index_of(item);
        if (index < 0) {
            return;
        }
        for (; index > 0; index--) {
            items[index] = items[index - 1];
        }
        items[0] = item;
    }

    /* Forgets everything that is not in the list. */
    public void keep_only(ulong[] allowed) {
        ulong[] kept = {};
        foreach (ulong item in items) {
            if (item in allowed) {
                kept += item;
            }
        }
        items = kept;
    }
}
