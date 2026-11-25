public struct Rect {
    public int x;
    public int y;
    public int width;
    public int height;

    public int right {
        get { return x + width; }
    }

    public int bottom {
        get { return y + height; }
    }

    public bool equals(Rect other) {
        return x == other.x && y == other.y && width == other.width && height == other.height;
    }

    public bool same_size(Rect other) {
        return width == other.width && height == other.height;
    }

    public int64 shared_area(Rect other) {
        int64 shared_width = int.min(right, other.right) - int.max(x, other.x);
        int64 shared_height = int.min(bottom, other.bottom) - int.max(y, other.y);
        return int64.max(0, shared_width) * int64.max(0, shared_height);
    }
}
