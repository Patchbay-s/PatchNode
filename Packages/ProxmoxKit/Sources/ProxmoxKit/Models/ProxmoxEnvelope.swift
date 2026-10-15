import Foundation

/// Proxmox wraps every response in `{"data": ...}`; `data` may be null.
struct ProxmoxEnvelope<Payload: Decodable>: Decodable {
    let data: Payload?
}
