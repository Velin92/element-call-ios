//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallHost
import ElementCallKit
import Foundation

/// One entry of the service interruptions list: what the user is told, grouped by whose side the
/// trouble is on (034 R13, R23, R29). Three at most, in this order, however many causes the core
/// reports; the tiles and the controls carry the detail.
public nonisolated enum ElementCallInterruption: Hashable, Sendable {
    /// Our homeserver does not answer. `isMembershipLapsed` once the others have dropped us (R17).
    ///
    /// Nothing says when someone is on the call whose membership has not reached us (R16's
    /// "unverifiable participant", the record's `unmappable`): they get no tile and, having no
    /// membership, none of our keys, so they can neither be seen nor hear us, and there is nothing
    /// for the user to do. They appear as an ordinary join when the server returns.
    case ownServer(isMembershipLapsed: Bool)
    /// Our own media server is being reconnected (R23).
    case ownMedia
    /// Somebody else's media is not reaching us, or cannot be decrypted (R29).
    case othersMedia
    
    /// The core's causes mapped to entries (R38). `signalling` is passed apart from the record
    /// because it is the only cause that exists before media does (C4): a join made during an
    /// outage has a server entry and no record yet. Members in `withinKeyGrace` are not counted as
    /// undecryptable: see ``MatrixRTCMediaSession/keyGrace``.
    ///
    /// Our media has no entry until it has connected once. The core reports the first connection
    /// to our SFU as a reconnection (C11), so every call would otherwise open with the indicator up
    /// for the seconds that takes, while the call is still connecting and says so already.
    static func entries(signalling: MatrixRTCSignallingHealth,
                        record: MatrixRTCInterruptions?,
                        withinKeyGrace: Set<String> = [],
                        hasMediaConnected: Bool = true) -> [ElementCallInterruption] {
        var entries: [ElementCallInterruption] = []
        var record = record ?? .none
        record.undecryptable.removeAll { withinKeyGrace.contains($0) }
        // A lapse with signalling back is the moment before the republish lands, and still true.
        if !signalling.isReachable || record.isOwnMembershipLapsed {
            entries.append(.ownServer(isMembershipLapsed: record.isOwnMembershipLapsed))
        }
        if hasMediaConnected, record.ownMedia != .connected {
            entries.append(.ownMedia)
        }
        if !record.membersReconnecting.isEmpty || !record.membersUnreachable.isEmpty || !record.undecryptable.isEmpty {
            entries.append(.othersMedia)
        }
        return entries
    }
    
    /// The entries for a controller's call, as the stage and the minimized bar both show them.
    @MainActor
    static func entries(for controller: ElementCallController) -> [ElementCallInterruption] {
        guard controller.isInCall else { return [] }
        return entries(signalling: controller.signalling,
                       record: controller.call?.interruptions,
                       withinKeyGrace: controller.call?.membersWithinKeyGrace ?? [],
                       hasMediaConnected: controller.connectedAt != nil)
    }
}
