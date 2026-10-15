import Foundation

/// Realistic payloads (Home Assistant 2024.x REST API, Glances 4.x and 3.x web
/// server). Hosts are `*.example.invalid`, credentials are fake.
enum Fixtures {
    static let homeAssistantURL = URL(string: "https://ha.example.invalid")!
    static let glancesURL = URL(string: "https://glances.example.invalid")!

    static let haToken = "fake-ha-token-1234"
    static let glancesCredential = "glances:fake-password-1234"

    // MARK: Home Assistant

    static let apiRunning = #"{"message":"API running."}"#

    /// `GET /api/states`: sensors with units, a scene, a script, a light, an
    /// unavailable entity and malformed entries that must be dropped.
    static let states = #"""
    [
      {
        "entity_id": "sensor.living_room_temperature",
        "state": "21.5",
        "attributes": {
          "state_class": "measurement",
          "unit_of_measurement": "°C",
          "device_class": "temperature",
          "friendly_name": "Living room temperature"
        },
        "last_changed": "2024-05-01T09:58:12.345678+00:00",
        "last_reported": "2024-05-01T09:59:40.000000+00:00",
        "last_updated": "2024-05-01T09:58:12.345678+00:00",
        "context": {"id": "01HWXFAKE0000000000000000", "parent_id": null, "user_id": null}
      },
      {
        "entity_id": "scene.movie_night",
        "state": "2024-04-30T20:15:00.000000+00:00",
        "attributes": {"entity_id": ["light.living_room"], "id": "1714500000000", "friendly_name": "Movie night"},
        "last_changed": "2024-04-30T20:15:00.000000+00:00",
        "last_updated": "2024-04-30T20:15:00.000000+00:00",
        "context": {"id": "01HWXFAKE0000000000000001", "parent_id": null, "user_id": null}
      },
      {
        "entity_id": "script.good_morning",
        "state": "off",
        "attributes": {"last_triggered": null, "mode": "single", "current": 0, "friendly_name": "Good morning"},
        "last_changed": "2024-05-01T06:00:00+02:00",
        "last_updated": "2024-05-01T06:00:00+02:00",
        "context": {"id": "01HWXFAKE0000000000000002", "parent_id": null, "user_id": null}
      },
      {
        "entity_id": "light.living_room",
        "state": "on",
        "attributes": {"supported_color_modes": ["brightness"], "color_mode": "brightness", "brightness": 180, "friendly_name": "Living room"},
        "last_changed": "2024-05-01T09:00:00.000000+00:00",
        "last_updated": "2024-05-01T09:00:00.000000+00:00",
        "context": {"id": "01HWXFAKE0000000000000003", "parent_id": null, "user_id": null}
      },
      {
        "entity_id": "sensor.garage_door_battery",
        "state": "unavailable",
        "attributes": {"unit_of_measurement": "", "friendly_name": ""},
        "last_changed": "not-a-date",
        "last_updated": "2024-05-01T08:00:00.000000+00:00",
        "context": {"id": "01HWXFAKE0000000000000004", "parent_id": null, "user_id": null}
      },
      {
        "entity_id": "sensor.power_meter",
        "state": 1234,
        "attributes": {"unit_of_measurement": "W", "device_class": "power"},
        "last_changed": "2024-05-01T09:59:00Z",
        "last_updated": "2024-05-01T09:59:00Z",
        "context": {"id": "01HWXFAKE0000000000000005", "parent_id": null, "user_id": null}
      },
      {"entity_id": "Sensor.Bad_Case", "state": "1", "attributes": {}},
      {"entity_id": "sensor/../../etc", "state": "1", "attributes": {}},
      {"entity_id": "no_dot_here", "state": "1", "attributes": {}},
      {"state": "orphan", "attributes": {"friendly_name": "No ID"}},
      "not-an-object",
      42
    ]
    """#

    // MARK: Glances

    /// `GET /api/4/all` (Glances 4.x), trimmed of the process list and network plugins
    /// but keeping unrelated plugins the decoder must skip.
    static let glancesV4 = #"""
    {
      "alert": [],
      "amps": [],
      "cloud": {},
      "connections": {},
      "core": {"phys": 4, "log": 8},
      "cpu": {"total": 12.3, "user": 8.1, "nice": 0.0, "system": 3.2, "idle": 87.7, "iowait": 0.4, "irq": 0.0, "steal": 0.0, "ctx_switches": 18234, "interrupts": 9123, "soft_interrupts": 4512, "syscalls": 0, "cpucore": 8, "time_since_update": 2.01},
      "diskio": [{"disk_name": "sda", "read_bytes": 0, "write_bytes": 4096, "key": "disk_name"}],
      "fs": [
        {"device_name": "/dev/sda2", "fs_type": "ext4", "mnt_point": "/", "options": "rw,relatime", "size": 250059350016, "used": 105024927744, "free": 132285480960, "percent": 42.0, "key": "mnt_point"},
        {"device_name": "/dev/md0", "fs_type": "ext4", "mnt_point": "/srv/data", "options": "rw,relatime", "size": 3998614962176, "used": 3558767316992, "free": 239847645184, "percent": 89.0, "key": "mnt_point"},
        {"device_name": "/dev/sdb1", "fs_type": "vfat", "mnt_point": "/boot/efi", "options": "rw", "size": 535805952, "used": 6291456, "free": 529514496, "percent": 1.2, "key": "mnt_point"},
        {"device_name": "/dev/sdz9", "fs_type": "ext4", "size": 1, "used": 1, "percent": 100.0, "key": "mnt_point"}
      ],
      "load": {"min1": 0.52, "min5": 0.61, "min15": 0.58, "cpucore": 8},
      "mem": {"total": 16681451520, "available": 9453445120, "percent": 43.3, "used": 7228006400, "free": 2130575360, "active": 6101200896, "inactive": 7283310592, "buffers": 432132096, "cached": 6890737664, "shared": 162570240},
      "memswap": {"total": 4294963200, "used": 137433088, "free": 4157530112, "percent": 3.2, "sin": 1024000, "sout": 2048000, "time_since_update": 2.01},
      "network": [{"interface_name": "eth0", "bytes_recv": 1024, "bytes_sent": 2048, "key": "interface_name"}],
      "processcount": {"total": 312, "running": 1, "sleeping": 311, "thread": 1045, "pid_max": 0},
      "quicklook": {"cpu": 12.3, "mem": 43.3, "swap": 3.2, "cpu_name": "Intel(R) Core(TM) i5-8500T CPU @ 2.10GHz", "cpu_hz_current": 2100000000.0, "cpu_hz": 2100000000.0},
      "sensors": [
        {"label": "Package id 0", "value": 52, "warning": 80, "critical": 100, "unit": "C", "type": "temperature_core", "key": "label"},
        {"label": "acpitz 1", "value": 27.8, "warning": null, "critical": null, "unit": "C", "type": "temperature_core", "key": "label"},
        {"label": "nvme0 Composite", "value": "41.9", "unit": "C", "type": "temperature_hdd", "key": "label"},
        {"label": "cpu_fan", "value": 1180, "warning": null, "critical": null, "unit": "R", "type": "fan_speed", "key": "label"},
        {"label": "BAT0", "value": 87, "unit": "%", "type": "battery", "key": "label"},
        {"label": "broken sensor", "value": null, "unit": "C", "type": "temperature_core", "key": "label"}
      ],
      "system": {"os_name": "Linux", "hostname": "nas", "platform": "64bit", "linux_distro": "Debian GNU/Linux 12", "os_version": "6.1.0-18-amd64", "hr_name": "Debian GNU/Linux 12 64bit / Linux 6.1.0-18-amd64"},
      "uptime": "5 days, 3:12:09",
      "version": "4.1.2"
    }
    """#

    /// `GET /api/3/all` (Glances 3.x): no `load.cpucore` (core count from `core.log`),
    /// empty `linux_distro`, a Fahrenheit sensor without `type`.
    static let glancesV3 = #"""
    {
      "core": {"phys": 2, "log": 4},
      "cpu": {"total": 71.4, "user": 60.2, "system": 11.2, "idle": 28.6, "cpucore": 4, "time_since_update": 3.0},
      "fs": [
        {"device_name": "/dev/mmcblk0p2", "fs_type": "ext4", "mnt_point": "/", "size": 31254540288, "used": 26566359040, "free": 3355443200, "percent": 85.0, "key": "mnt_point"}
      ],
      "load": {"min1": 2.1, "min5": 1.8, "min15": 1.5},
      "mem": {"total": 3978178560, "available": 318254284, "percent": 92.0, "used": 3659924276, "free": 118254284},
      "memswap": {"total": 104853504, "used": 52426752, "free": 52426752, "percent": 50.0},
      "sensors": [
        {"label": "cpu_thermal 0", "value": 131.0, "unit": "F", "key": "label"},
        {"label": "fan1", "value": 3000, "unit": "R", "type": "fan_speed", "key": "label"}
      ],
      "system": {"os_name": "Linux", "hostname": "raspberrypi", "platform": "32bit", "linux_distro": "", "os_version": "5.10.103-v7+"},
      "uptime": "12 days, 0:04:51"
    }
    """#

    /// A JSON object that is not a Glances payload (e.g. a reverse proxy page).
    static let notGlances = #"{"status":"ok","service":"nginx","message":"Welcome"}"#

    static let notFound = #"{"detail":"Not Found"}"#
}
