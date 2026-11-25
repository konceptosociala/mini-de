/* Copies of string lists with or without an item. */
namespace StringLists {
    public string[] with(string[] list, string item) {
        string[] result = list;
        if (!(item in list)) {
            result += item;
        }
        return result;
    }

    public string[] without(string[] list, string item) {
        string[] result = {};
        foreach (unowned string other in list) {
            if (other != item) {
                result += other;
            }
        }
        return result;
    }
}
