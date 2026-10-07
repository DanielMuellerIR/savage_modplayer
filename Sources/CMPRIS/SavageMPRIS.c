#include "SavageMPRIS.h"
#include <dbus/dbus.h>
#include <math.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define ROOT "org.mpris.MediaPlayer2"
#define PLAYER ROOT ".Player"
#define PROPS "org.freedesktop.DBus.Properties"
#define PATH "/org/mpris/MediaPlayer2"
_Static_assert(sizeof(double) == sizeof(unsigned long long), "Gain storage must fit a double");
_Static_assert(ATOMIC_LLONG_LOCK_FREE == 2, "MPRIS meters require lock-free 64-bit atomics");

struct SavageMPRIS {
    DBusConnection *connection;
    char *title, *uri;
    char track_path[96];
    const char *status;
    double sample_rate;
    int can_next, can_previous;
    _Atomic unsigned long long frames, gain_bits;
};

typedef struct { const char *interface, *name, *signature; int writable; } Property;
static const Property properties[] = {
    {ROOT, "CanQuit", "b", 0}, {ROOT, "CanRaise", "b", 0},
    {ROOT, "HasTrackList", "b", 0}, {ROOT, "Identity", "s", 0},
    {ROOT, "DesktopEntry", "s", 0}, {ROOT, "SupportedUriSchemes", "as", 0},
    {ROOT, "SupportedMimeTypes", "as", 0},
    {PLAYER, "PlaybackStatus", "s", 0}, {PLAYER, "Rate", "d", 1},
    {PLAYER, "Metadata", "a{sv}", 0}, {PLAYER, "Volume", "d", 1},
    {PLAYER, "Position", "x", 0}, {PLAYER, "MinimumRate", "d", 0},
    {PLAYER, "MaximumRate", "d", 0}, {PLAYER, "CanGoNext", "b", 0},
    {PLAYER, "CanGoPrevious", "b", 0}, {PLAYER, "CanPlay", "b", 0},
    {PLAYER, "CanPause", "b", 0}, {PLAYER, "CanSeek", "b", 0},
    {PLAYER, "CanControl", "b", 0}
};
#define PROPERTY_COUNT (sizeof(properties) / sizeof(properties[0]))

static int basic(DBusMessageIter *iter, int type, const void *value) {
    return dbus_message_iter_append_basic(iter, type, value);
}
static int metadata_entry(DBusMessageIter *array, const char *name,
                          const char *signature, int type, const char *value) {
    DBusMessageIter entry, variant;
    return dbus_message_iter_open_container(array, DBUS_TYPE_DICT_ENTRY, NULL, &entry)
        && basic(&entry, DBUS_TYPE_STRING, &name)
        && dbus_message_iter_open_container(&entry, DBUS_TYPE_VARIANT, signature, &variant)
        && basic(&variant, type, &value)
        && dbus_message_iter_close_container(&entry, &variant)
        && dbus_message_iter_close_container(array, &entry);
}
static int property_value(SavageMPRIS *s, DBusMessageIter *iter, const Property *p) {
    const char *name = p->name;
    if (!strcmp(p->signature, "b")) {
        dbus_bool_t value = !strcmp(name, "CanQuit") || !strcmp(name, "CanPlay")
            || !strcmp(name, "CanPause") || !strcmp(name, "CanControl");
        if (!strcmp(name, "CanGoNext")) value = s->can_next;
        if (!strcmp(name, "CanGoPrevious")) value = s->can_previous;
        return basic(iter, DBUS_TYPE_BOOLEAN, &value);
    }
    if (!strcmp(p->signature, "s")) {
        const char *value = !strcmp(name, "Identity") ? "Savage Mod Player"
            : !strcmp(name, "DesktopEntry") ? "savage-cli" : s->status;
        return basic(iter, DBUS_TYPE_STRING, &value);
    }
    if (!strcmp(p->signature, "d")) {
        double value = !strcmp(name, "Volume") ? savage_mpris_gain(s) : 1.0;
        return basic(iter, DBUS_TYPE_DOUBLE, &value);
    }
    if (!strcmp(p->signature, "x")) {
        dbus_int64_t value = (dbus_int64_t)(atomic_load_explicit(&s->frames,
            memory_order_relaxed) * (1000000.0 / s->sample_rate));
        return basic(iter, DBUS_TYPE_INT64, &value);
    }
    DBusMessageIter array;
    const int metadata = !strcmp(name, "Metadata");
    if (!dbus_message_iter_open_container(iter, DBUS_TYPE_ARRAY,
                                         metadata ? "{sv}" : "s", &array)) return 0;
    if (metadata && (!metadata_entry(&array, "mpris:trackid", "o", DBUS_TYPE_OBJECT_PATH, s->track_path)
        || !metadata_entry(&array, "xesam:title", "s", DBUS_TYPE_STRING, s->title)
        || !metadata_entry(&array, "xesam:url", "s", DBUS_TYPE_STRING, s->uri))) return 0;
    return dbus_message_iter_close_container(iter, &array);
}
static int property_entry(SavageMPRIS *s, DBusMessageIter *array, const Property *p) {
    DBusMessageIter entry, variant;
    return dbus_message_iter_open_container(array, DBUS_TYPE_DICT_ENTRY, NULL, &entry)
        && basic(&entry, DBUS_TYPE_STRING, &p->name)
        && dbus_message_iter_open_container(&entry, DBUS_TYPE_VARIANT, p->signature, &variant)
        && property_value(s, &variant, p)
        && dbus_message_iter_close_container(&entry, &variant)
        && dbus_message_iter_close_container(array, &entry);
}
static void send_message(SavageMPRIS *s, DBusMessage *message, int complete) {
    if (!message) return;
    if (complete) dbus_connection_send(s->connection, message, NULL);
    dbus_message_unref(message);
}
static void changed(SavageMPRIS *s, const char *name) {
    DBusMessage *message = dbus_message_new_signal(PATH, PROPS, "PropertiesChanged");
    if (!message) return;
    DBusMessageIter iter, array, invalidated;
    dbus_message_iter_init_append(message, &iter);
    const char *interface = PLAYER;
    int ok = basic(&iter, DBUS_TYPE_STRING, &interface)
        && dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, "{sv}", &array);
    for (size_t i = 0; ok && i < PROPERTY_COUNT; ++i)
        if (!strcmp(properties[i].interface, PLAYER) && !strcmp(properties[i].name, name))
            ok = property_entry(s, &array, &properties[i]);
    ok = ok && dbus_message_iter_close_container(&iter, &array)
        && dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, "s", &invalidated)
        && dbus_message_iter_close_container(&iter, &invalidated);
    send_message(s, message, ok);
}
static void error_reply(SavageMPRIS *s, DBusMessage *request, const char *name, const char *detail) {
    send_message(s, dbus_message_new_error(request, name, detail), 1);
}
static void empty_reply(SavageMPRIS *s, DBusMessage *request) {
    send_message(s, dbus_message_new_method_return(request), 1);
}
static int known_interface(const char *name) {
    return !strcmp(name, ROOT) || !strcmp(name, PLAYER);
}
static SavageMPRISCommand property_request(SavageMPRIS *s, DBusMessage *request) {
    const char *member = dbus_message_get_member(request);
    const int get = !strcmp(member, "Get"), all = !strcmp(member, "GetAll"), set = !strcmp(member, "Set");
    if (!get && !all && !set) {
        error_reply(s, request, DBUS_ERROR_UNKNOWN_METHOD, "Unknown property method");
        return SAVAGE_MPRIS_NONE;
    }
    if (!dbus_message_has_signature(request, all ? "s" : set ? "ssv" : "ss")) {
        error_reply(s, request, DBUS_ERROR_INVALID_ARGS, "Unexpected property arguments");
        return SAVAGE_MPRIS_NONE;
    }
    DBusMessageIter iter;
    dbus_message_iter_init(request, &iter);
    const char *interface, *name = NULL;
    dbus_message_iter_get_basic(&iter, &interface);
    if (!known_interface(interface)) {
        error_reply(s, request, DBUS_ERROR_UNKNOWN_INTERFACE, "Unknown interface");
        return SAVAGE_MPRIS_NONE;
    }
    const Property *property = NULL;
    if (!all) {
        dbus_message_iter_next(&iter);
        dbus_message_iter_get_basic(&iter, &name);
        for (size_t i = 0; i < PROPERTY_COUNT; ++i)
            if (!strcmp(interface, properties[i].interface) && !strcmp(name, properties[i].name)) property = &properties[i];
        if (!property) {
            error_reply(s, request, DBUS_ERROR_UNKNOWN_PROPERTY, "Unknown property");
            return SAVAGE_MPRIS_NONE;
        }
    }
    if (set) {
        if (!property->writable) {
            error_reply(s, request, DBUS_ERROR_PROPERTY_READ_ONLY, "Property is read-only");
            return SAVAGE_MPRIS_NONE;
        }
        if (strcmp(name, "Rate") && strcmp(name, "Volume")) {
            error_reply(s, request, DBUS_ERROR_NOT_SUPPORTED, "This setting is fixed");
            return SAVAGE_MPRIS_NONE;
        }
        dbus_message_iter_next(&iter);
        DBusMessageIter variant;
        dbus_message_iter_recurse(&iter, &variant);
        if (dbus_message_iter_get_arg_type(&variant) != DBUS_TYPE_DOUBLE) {
            error_reply(s, request, DBUS_ERROR_INVALID_ARGS, "Expected a double value");
            return SAVAGE_MPRIS_NONE;
        }
        double value;
        dbus_message_iter_get_basic(&variant, &value);
        if (!isfinite(value)) {
            error_reply(s, request, DBUS_ERROR_INVALID_ARGS, "Expected a finite value");
            return SAVAGE_MPRIS_NONE;
        }
        SavageMPRISCommand command = SAVAGE_MPRIS_NONE;
        if (!strcmp(name, "Volume")) {
            value = fmax(0, fmin(1, value));
            unsigned long long bits;
            memcpy(&bits, &value, sizeof(bits));
            atomic_store_explicit(&s->gain_bits, bits, memory_order_relaxed);
            changed(s, "Volume");
        } else if (value == 0) command = SAVAGE_MPRIS_PAUSE;
        empty_reply(s, request);
        return command;
    }
    DBusMessage *reply = dbus_message_new_method_return(request);
    if (!reply) return SAVAGE_MPRIS_NONE;
    DBusMessageIter out, container;
    dbus_message_iter_init_append(reply, &out);
    int ok = dbus_message_iter_open_container(&out, all ? DBUS_TYPE_ARRAY : DBUS_TYPE_VARIANT,
                                             all ? "{sv}" : property->signature, &container);
    if (all) {
        for (size_t i = 0; ok && i < PROPERTY_COUNT; ++i)
            if (!strcmp(interface, properties[i].interface)) ok = property_entry(s, &container, &properties[i]);
    } else if (ok) ok = property_value(s, &container, property);
    ok = ok && dbus_message_iter_close_container(&out, &container);
    send_message(s, reply, ok);
    return SAVAGE_MPRIS_NONE;
}

static void xml_append(char *xml, size_t capacity, size_t *used, const char *format, ...) {
    if (*used >= capacity) return;
    va_list arguments;
    va_start(arguments, format);
    int written = vsnprintf(xml + *used, capacity - *used, format, arguments);
    va_end(arguments);
    if (written < 0 || (size_t)written >= capacity - *used) *used = capacity;
    else *used += (size_t)written;
}
static void introspect(SavageMPRIS *s, DBusMessage *request) {
    // Properties werden aus derselben Tabelle wie Get/GetAll beschrieben.
    char xml[8192];
    size_t used = 0;
    xml_append(xml, sizeof(xml), &used,
        "<node><interface name='%s'><method name='Raise'/><method name='Quit'/>", ROOT);
    for (int part = 0; part < 2; ++part) {
        const char *interface = part == 0 ? ROOT : PLAYER;
        if (part == 1) xml_append(xml, sizeof(xml), &used,
            "</interface><interface name='%s'>"
            "<method name='Next'/><method name='Previous'/><method name='Pause'/>"
            "<method name='PlayPause'/><method name='Stop'/><method name='Play'/>"
            "<method name='Seek'><arg type='x' direction='in'/></method>"
            "<method name='SetPosition'><arg type='o' direction='in'/><arg type='x' direction='in'/></method>"
            "<method name='OpenUri'><arg type='s' direction='in'/></method>"
            "<signal name='Seeked'><arg type='x'/></signal>", PLAYER);
        for (size_t i = 0; i < PROPERTY_COUNT; ++i) if (!strcmp(interface, properties[i].interface))
            xml_append(xml, sizeof(xml), &used,
                "<property name='%s' type='%s' access='%s'><annotation name='org.freedesktop.DBus.Property.EmitsChangedSignal' value='%s'/></property>",
                properties[i].name, properties[i].signature, properties[i].writable ? "readwrite" : "read",
                !strcmp(properties[i].name, "Position") || !strcmp(properties[i].name, "CanControl") ? "false" : "true");
    }
    xml_append(xml, sizeof(xml), &used,
        "</interface><interface name='%s'>"
        "<method name='Get'><arg type='s' direction='in'/><arg type='s' direction='in'/><arg type='v' direction='out'/></method>"
        "<method name='GetAll'><arg type='s' direction='in'/><arg type='a{sv}' direction='out'/></method>"
        "<method name='Set'><arg type='s' direction='in'/><arg type='s' direction='in'/><arg type='v' direction='in'/></method>"
        "<signal name='PropertiesChanged'><arg type='s'/><arg type='a{sv}'/><arg type='as'/></signal>"
        "</interface><interface name='org.freedesktop.DBus.Introspectable'>"
        "<method name='Introspect'><arg type='s' direction='out'/></method></interface>"
        "<interface name='org.freedesktop.DBus.Peer'><method name='Ping'/></interface></node>", PROPS);
    if (used >= sizeof(xml)) { error_reply(s, request, DBUS_ERROR_FAILED, "Introspection overflow"); return; }
    DBusMessage *reply = dbus_message_new_method_return(request);
    if (!reply) return;
    DBusMessageIter iter;
    dbus_message_iter_init_append(reply, &iter);
    const char *value = xml;
    send_message(s, reply, basic(&iter, DBUS_TYPE_STRING, &value));
}
SavageMPRIS *savage_mpris_create(double sample_rate) {
    if (!isfinite(sample_rate) || sample_rate <= 0 || sample_rate > 768000) return NULL;
    SavageMPRIS *s = calloc(1, sizeof(*s));
    if (!s) return NULL;
    s->sample_rate = sample_rate;
    s->status = "Stopped";
    s->title = strdup(""); s->uri = strdup("");
    snprintf(s->track_path, sizeof(s->track_path), PATH "/TrackList/NoTrack");
    double gain = 1;
    unsigned long long bits; memcpy(&bits, &gain, sizeof(bits));
    atomic_init(&s->gain_bits, bits); atomic_init(&s->frames, 0);
    s->connection = dbus_bus_get_private(DBUS_BUS_SESSION, NULL);
    if (!s->title || !s->uri || !s->connection) { savage_mpris_destroy(s); return NULL; }
    dbus_connection_set_exit_on_disconnect(s->connection, FALSE);
    char name[96]; snprintf(name, sizeof(name), ROOT ".savage.instance%ld", (long)getpid());
    if (dbus_bus_request_name(s->connection, name, DBUS_NAME_FLAG_DO_NOT_QUEUE, NULL)
            != DBUS_REQUEST_NAME_REPLY_PRIMARY_OWNER) { savage_mpris_destroy(s); return NULL; }
    return s;
}
void savage_mpris_destroy(SavageMPRIS *s) {
    if (!s) return;
    if (s->connection) { dbus_connection_close(s->connection); dbus_connection_unref(s->connection); }
    free(s->title); free(s->uri); free(s);
}
void savage_mpris_track(SavageMPRIS *s, const char *title, const char *uri,
                        uint64_t track_id, int can_next, int can_previous) {
    char *new_title = strdup(title), *new_uri = strdup(uri);
    if (!new_title || !new_uri) { free(new_title); free(new_uri); return; }
    free(s->title); free(s->uri); s->title = new_title; s->uri = new_uri;
    snprintf(s->track_path, sizeof(s->track_path), "/org/savage_modplayer/track/%llu", (unsigned long long)track_id);
    atomic_store_explicit(&s->frames, 0, memory_order_relaxed);
    s->can_next = can_next; s->can_previous = can_previous;
    changed(s, "Metadata"); changed(s, "CanGoNext"); changed(s, "CanGoPrevious");
}
void savage_mpris_status(SavageMPRIS *s, const char *status) {
    if (!strcmp(s->status, status)) return;
    // Aufrufer übergeben ausschließlich diese langlebigen Zustandskonstanten.
    s->status = !strcmp(status, "Playing") ? "Playing" : !strcmp(status, "Paused") ? "Paused" : "Stopped";
    changed(s, "PlaybackStatus");
}
double savage_mpris_gain(const SavageMPRIS *s) {
    unsigned long long bits = atomic_load_explicit(&s->gain_bits, memory_order_relaxed);
    double value; memcpy(&value, &bits, sizeof(value)); return value;
}
void savage_mpris_add_frames(SavageMPRIS *s, uint64_t frames) {
    atomic_fetch_add_explicit(&s->frames, frames, memory_order_relaxed);
}
SavageMPRISCommand savage_mpris_poll(SavageMPRIS *s) {
    if (!dbus_connection_read_write(s->connection, 0)) return SAVAGE_MPRIS_NONE;
    // Ein Client darf die Audiosteuerung nicht durch eine endlose Bus-Schleife blockieren.
    for (int count = 0; count < 32; ++count) {
        DBusMessage *request = dbus_connection_pop_message(s->connection);
        if (!request) break;
        SavageMPRISCommand command = SAVAGE_MPRIS_NONE;
        if (dbus_message_get_type(request) != DBUS_MESSAGE_TYPE_METHOD_CALL) { dbus_message_unref(request); continue; }
        const char *path = dbus_message_get_path(request), *interface = dbus_message_get_interface(request);
        const char *member = dbus_message_get_member(request);
        if (!path || strcmp(path, PATH)) error_reply(s, request, DBUS_ERROR_UNKNOWN_OBJECT, "Unknown object");
        else if (!interface || !member) error_reply(s, request, DBUS_ERROR_UNKNOWN_METHOD, "Missing method interface");
        else if (!strcmp(interface, PROPS)) command = property_request(s, request);
        else if (!strcmp(interface, "org.freedesktop.DBus.Introspectable") && !strcmp(member, "Introspect")
                 && dbus_message_has_signature(request, "")) introspect(s, request);
        else if (!strcmp(interface, "org.freedesktop.DBus.Peer") && !strcmp(member, "Ping")
                 && dbus_message_has_signature(request, "")) empty_reply(s, request);
        else if (!strcmp(interface, ROOT) && !strcmp(member, "Quit") && dbus_message_has_signature(request, "")) {
            empty_reply(s, request); command = SAVAGE_MPRIS_QUIT;
        } else if (!strcmp(interface, ROOT) && !strcmp(member, "Raise") && dbus_message_has_signature(request, "")) {
            error_reply(s, request, DBUS_ERROR_NOT_SUPPORTED, "No graphical interface");
        } else if (!strcmp(interface, PLAYER)) {
            const char *signature = !strcmp(member, "Seek") ? "x" : !strcmp(member, "SetPosition") ? "ox"
                : !strcmp(member, "OpenUri") ? "s" : "";
            if (!dbus_message_has_signature(request, signature)) error_reply(s, request, DBUS_ERROR_INVALID_ARGS, "Unexpected method arguments");
            else {
                if (!strcmp(member, "Play")) command = SAVAGE_MPRIS_PLAY;
                else if (!strcmp(member, "Pause")) command = SAVAGE_MPRIS_PAUSE;
                else if (!strcmp(member, "PlayPause")) command = SAVAGE_MPRIS_TOGGLE;
                else if (!strcmp(member, "Stop")) command = SAVAGE_MPRIS_STOP;
                else if (!strcmp(member, "Next")) command = s->can_next ? SAVAGE_MPRIS_NEXT : SAVAGE_MPRIS_NONE;
                else if (!strcmp(member, "Previous")) command = s->can_previous ? SAVAGE_MPRIS_PREVIOUS : SAVAGE_MPRIS_NONE;
                else if (!strcmp(member, "OpenUri")) {
                    error_reply(s, request, DBUS_ERROR_NOT_SUPPORTED, "Opening URIs is unavailable");
                    dbus_message_unref(request); continue;
                } else if (strcmp(member, "Seek") && strcmp(member, "SetPosition")) {
                    error_reply(s, request, DBUS_ERROR_UNKNOWN_METHOD, "Unsupported method");
                    dbus_message_unref(request); continue;
                }
                empty_reply(s, request);
            }
        } else error_reply(s, request, DBUS_ERROR_UNKNOWN_METHOD, "Unsupported method");
        dbus_message_unref(request);
        if (command != SAVAGE_MPRIS_NONE) { dbus_connection_flush(s->connection); return command; }
    }
    dbus_connection_flush(s->connection);
    return SAVAGE_MPRIS_NONE;
}
