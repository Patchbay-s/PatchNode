import Foundation

/// Realistic payloads (Prometheus 2.x/3.x, Alertmanager 0.27 v2, Grafana 11,
/// Uptime Kuma 1.23/2.0). Hosts are `*.example.invalid`, credentials are fake.
enum Fixtures {
    static let prometheusURL = URL(string: "https://prometheus.example.invalid")!
    static let alertmanagerURL = URL(string: "https://alertmanager.example.invalid")!
    static let grafanaURL = URL(string: "https://grafana.example.invalid")!
    static let kumaStatusURL = URL(string: "https://kuma.example.invalid/status/homelab")!

    static let basicCredential = "PatchNode:fake-password-1234"
    static let grafanaToken = "glsa_fake-grafana-token-1234"

    // MARK: Prometheus

    static let buildinfo = #"""
    {"status":"success","data":{"version":"3.1.0","revision":"fake","branch":"HEAD","buildUser":"root@example.invalid","buildDate":"20241216-00:00:00","goVersion":"go1.23.4"}}
    """#

    static let vector = #"""
    {"status":"success","data":{"resultType":"vector","result":[
      {"metric":{"__name__":"up","instance":"node.example.invalid:9100","job":"node"},"value":[1714557600.123,"1"]},
      {"metric":{"__name__":"up","instance":"cadvisor.example.invalid:8080","job":"cadvisor"},"value":[1714557600.123,"0.5"]},
      {"metric":{"__name__":"up","instance":"nan.example.invalid:9100","job":"node"},"value":[1714557600.123,"NaN"]}
    ]},"warnings":[]}
    """#

    static let matrix = #"""
    {"status":"success","data":{"resultType":"matrix","result":[
      {"metric":{"instance":"node.example.invalid:9100","job":"node","mode":"idle"},"values":[
        [1714557600,"0.5"],[1714557615,"NaN"],[1714557630,"+Inf"],[1714557645,"-Inf"],[1714557660,"0.75"]
      ]},
      "garbage-series",
      {"metric":{"job":"node"},"values":[[1714557600,"12"],["1714557615","13.5"]]}
    ]}}
    """#

    static let scalar = #"""
    {"status":"success","data":{"resultType":"scalar","result":[1714557600.5,"42.5"]}}
    """#

    static let scalarNaN = #"""
    {"status":"success","data":{"resultType":"scalar","result":[1714557600.5,"NaN"]}}
    """#

    static let stringResult = #"""
    {"status":"success","data":{"resultType":"string","result":[1714557600,"hello PatchNode"]}}
    """#

    static let emptyVector = #"""
    {"status":"success","data":{"resultType":"vector","result":[]}}
    """#

    static let badData = #"""
    {"status":"error","errorType":"bad_data","error":"invalid parameter \"query\": 1:4: parse error: unexpected \"}\" in label matching, expected string"}
    """#

    static func badData(message: String) -> String {
        #"{"status":"error","errorType":"bad_data","error":"\#(message)"}"#
    }

    static let statusErrorOn200 = #"""
    {"status":"error","errorType":"internal","error":"something odd"}
    """#

    static let missingData = #"{"status":"success"}"#

    static let targets = #"""
    {"status":"success","data":{"activeTargets":[
      {"discoveredLabels":{"__address__":"node.example.invalid:9100","__metrics_path__":"/metrics","__scheme__":"http","job":"node"},
       "labels":{"instance":"node.example.invalid:9100","job":"node"},
       "scrapePool":"node","scrapeUrl":"http://node.example.invalid:9100/metrics","globalUrl":"http://node.example.invalid:9100/metrics",
       "lastError":"","lastScrape":"2024-05-01T10:00:00.123456789Z","lastScrapeDuration":0.012,"health":"up",
       "scrapeInterval":"15s","scrapeTimeout":"10s"},
      {"discoveredLabels":{"__address__":"nas.example.invalid:9100","job":"node"},
       "labels":{"instance":"nas.example.invalid:9100","job":"node"},
       "scrapePool":"node","scrapeUrl":"http://nas.example.invalid:9100/metrics",
       "lastError":"Get \"http://nas.example.invalid:9100/metrics\": dial tcp: connect: connection refused",
       "lastScrape":"2024-05-01T11:59:58+02:00","lastScrapeDuration":0.001,"health":"down",
       "scrapeInterval":"15s","scrapeTimeout":"10s"},
      {"labels":{"instance":"new.example.invalid:9100","job":"blackbox"},
       "scrapePool":"blackbox","scrapeUrl":"http://new.example.invalid:9100/probe",
       "lastError":"","lastScrape":"0001-01-01T00:00:00Z","lastScrapeDuration":0,"health":"unknown"},
      42
    ],"droppedTargets":[]}}
    """#

    static let emptyTargets = #"{"status":"success","data":{"activeTargets":[],"droppedTargets":[]}}"#

    // MARK: Alertmanager 0.27 (also served by Grafana unified alerting)

    static let alertmanagerAlerts = #"""
    [
      {"annotations":{"summary":"Instance node.example.invalid:9100 down","description":"Target unreachable for 5 minutes"},
       "endsAt":"2024-05-01T10:15:00.000Z","fingerprint":"a1b2c3d4e5f60718",
       "receivers":[{"name":"default"}],"startsAt":"2024-05-01T09:55:12.345Z",
       "status":{"inhibitedBy":[],"silencedBy":[],"state":"active"},
       "updatedAt":"2024-05-01T10:00:12.345Z","generatorURL":"https://prometheus.example.invalid/graph?g0.expr=up+%3D%3D+0",
       "labels":{"alertname":"InstanceDown","instance":"node.example.invalid:9100","job":"node","severity":"critical"}},
      {"annotations":{"description":"Disk /data at 91%","message":"ignored"},
       "endsAt":"2024-05-01T10:15:00.000Z","receivers":[{"name":"default"}],"startsAt":"2024-05-01T08:00:00Z",
       "status":{"inhibitedBy":[],"silencedBy":[],"state":"active"},
       "labels":{"alertname":"DiskAlmostFull","instance":"nas.example.invalid:9100","severity":"warning"}},
      {"annotations":{"message":"Backup older than 24 h"},"fingerprint":"0f0e0d0c0b0a0908",
       "startsAt":"2024-05-01T07:00:00.5+02:00","status":{"inhibitedBy":[],"silencedBy":[],"state":"active"},
       "labels":{"alertname":"BackupStale","severity":"info"}},
      {"annotations":{"summary":"Silenced one"},"fingerprint":"ffffffffffffffff","startsAt":"2024-05-01T09:00:00Z",
       "status":{"inhibitedBy":[],"silencedBy":["5f1b0d2a-fake"],"state":"suppressed"},
       "labels":{"alertname":"Silenced","severity":"critical"}},
      "not-an-alert"
    ]
    """#

    // MARK: Grafana 11

    static let grafanaSearch = #"""
    [
      {"id":12,"uid":"node-exporter","orgId":1,"title":"Node Exporter Full","uri":"db/node-exporter-full",
       "url":"/d/node-exporter/node-exporter-full","slug":"","type":"dash-db","tags":["linux","prometheus"],
       "isStarred":false,"folderId":3,"folderUid":"infra","folderTitle":"Infrastructure",
       "folderUrl":"/dashboards/f/infra/","sortMeta":0,"isDeleted":false},
      {"id":13,"orgId":1,"title":"Broken entry without uid","type":"dash-db","tags":[]},
      {"id":14,"uid":"home","orgId":1,"title":"Home","uri":"db/home","url":"/d/home/home","slug":"",
       "type":"dash-db","tags":[],"isStarred":true,"sortMeta":0,"isDeleted":false}
    ]
    """#

    static let grafanaAlerts = #"""
    [
      {"annotations":{"summary":"CPU above 90% on proxmox.example.invalid","__orgId__":"1"},
       "endsAt":"2024-05-01T10:04:00Z","fingerprint":"5e8c7b6a59483726","receivers":[{"name":"grafana-default-email"}],
       "startsAt":"2024-05-01T09:40:00Z","status":{"inhibitedBy":[],"silencedBy":[],"state":"active"},
       "updatedAt":"2024-05-01T10:00:00.000Z","generatorURL":"https://grafana.example.invalid/alerting/grafana/abc/view",
       "labels":{"__alert_rule_title__":"High CPU","__alert_rule_uid__":"abc","grafana_folder":"Infra","severity":"page"}}
    ]
    """#

    // MARK: Uptime Kuma 1.23 / 2.0

    static let kumaStatusPage = #"""
    {"config":{"slug":"homelab","title":"Homelab","description":null,"icon":"/icon.svg","theme":"auto",
      "published":true,"showTags":false,"domainNameList":[],"customCSS":"","footerText":null,
      "showPoweredBy":true,"googleAnalyticsId":null,"showCertificateExpiry":false},
     "incident":null,
     "publicGroupList":[
      {"id":1,"name":"Services","weight":1,"monitorList":[
        {"id":1,"name":"Nextcloud","sendUrl":0,"type":"http"},
        {"id":2,"name":"Jellyfin","sendUrl":0,"type":"http"}]},
      {"id":2,"name":"Infra","weight":2,"monitorList":[
        {"id":3,"name":"NAS","sendUrl":0,"type":"ping"},
        {"name":"entry without id"},
        {"id":"4","name":"Router","sendUrl":0,"type":"ping"}]}
     ],
     "maintenanceList":[]}
    """#

    static let kumaHeartbeats = #"""
    {"heartbeatList":{
      "1":[{"status":1,"time":"2024-05-01 09:59:00.456","msg":"","ping":42},
           {"status":1,"time":"2024-05-01 10:00:00.123","msg":"200 - OK","ping":38.5}],
      "2":[{"status":1,"time":"2024-05-01 09:59:00","msg":"200 - OK","ping":12},
           {"status":0,"time":"2024-05-01T10:00:00.250Z","msg":"timeout of 48000ms exceeded","ping":null}],
      "3":[]
     },
     "uptimeList":{"1_24":0.9993,"2_24":"0.95","1_720":0.99}}
    """#

    static func kumaHeartbeats(monitorID: Int, statuses: [Int]) -> String {
        let beats = statuses.enumerated().map { index, status in
            #"{"status":\#(status),"time":"2024-05-01 10:\#(String(format: "%02d", index)):00","msg":"beat \#(index)","ping":10}"#
        }
        return #"{"heartbeatList":{"\#(monitorID)":[\#(beats.joined(separator: ","))]},"uptimeList":{}}"#
    }
}
