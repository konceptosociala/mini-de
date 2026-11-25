/* The part of the D-Bus interface of BlueZ that the menu uses. */
namespace Bluez {
    public const string NAME = "org.bluez";
    public const string ADAPTER_INTERFACE = "org.bluez.Adapter1";
    public const string DEVICE_INTERFACE = "org.bluez.Device1";
    public const string BATTERY_INTERFACE = "org.bluez.Battery1";

    [DBus (name = "org.freedesktop.DBus.ObjectManager")]
    public interface ObjectManager : Object {
        public abstract async HashTable<ObjectPath, HashTable<string, HashTable<string, Variant>>>
            get_managed_objects() throws DBusError, IOError;
    }

    [DBus (name = "org.freedesktop.DBus.Properties")]
    public interface Properties : Object {
        public abstract async void set(
            string interface_name,
            string property,
            Variant value
        ) throws DBusError, IOError;
    }

    [DBus (name = "org.bluez.Adapter1")]
    public interface Adapter : Object {
        public abstract async void start_discovery() throws DBusError, IOError;
        public abstract async void stop_discovery() throws DBusError, IOError;
        public abstract async void remove_device(ObjectPath device) throws DBusError, IOError;
    }

    [DBus (name = "org.bluez.Device1", timeout = 90000)]
    public interface Device : Object {
        [DBus (name = "Connect")]
        public abstract async void connect_device() throws DBusError, IOError;
        [DBus (name = "Disconnect")]
        public abstract async void disconnect_device() throws DBusError, IOError;
        public abstract async void pair() throws DBusError, IOError;
    }

    [DBus (name = "org.bluez.AgentManager1")]
    public interface AgentManager : Object {
        public abstract async void register_agent(
            ObjectPath agent,
            string capability
        ) throws DBusError, IOError;
        public abstract async void unregister_agent(ObjectPath agent) throws DBusError, IOError;
    }

    public async void set_flag(
        string path,
        string interface_name,
        string property,
        bool value
    ) throws Error {
        Properties properties = yield Bus.get_proxy(BusType.SYSTEM, NAME, path);
        yield properties.set(interface_name, property, new Variant.boolean(value));
    }
}
