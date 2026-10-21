//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallKit
import Foundation

/// One entry of the service interruptions list: what the user is told, grouped by whose side the
/// trouble is on (034 R13, R23, R29). Three at most, in this order, however many causes the core
/// reports; the tiles and the controls carry the detail.
public nonisolated enum ElementCallInterruption: Hashable, Sendable {
    /// Our homeserver does not answer. `isMembershipLapsed` once the others have dropped us and can
    /// no longer see or hear us (R17); `hasUnverifiedParticipant` while someone is on the call whose
    /// identity cannot be checked until it answers again (R16).
    case ownServer(isMembershipLapsed: Bool, hasUnverifiedParticipant: Bool)
    /// Our own media server is being reconnected (R23).
    case ownMedia
    /// Somebody else's media is not reaching us, or cannot be decrypted (R29).
    case othersMedia
    
    /// The core's causes mapped to entries (R38). `signalling` is passed apart from the record
    /// because it is the only cause that exists before media does (C4): a join made during an
    /// outage has a server entry and no record yet.
    static func entries(signalling: MatrixRTCSignallingHealth, record: MatrixRTCInterruptions?) -> [ElementCallInterruption] {
        var entries: [ElementCallInterruption] = []
        let record = record ?? .none
        // A lapse with signalling back is the moment before the republish lands, and still true.
        if !signalling.isReachable || record.isOwnMembershipLapsed {
            // An unmappable participant alone is not an entry: one shows up for a moment on every
            // ordinary join, the transport being quicker than the membership. It means something
            // only while the homeserver that would introduce them cannot.
            entries.append(.ownServer(isMembershipLapsed: record.isOwnMembershipLapsed,
                                      hasUnverifiedParticipant: !record.unmappable.isEmpty))
        }
        if record.ownMedia != .connected {
            entries.append(.ownMedia)
        }
        if !record.membersReconnecting.isEmpty || !record.membersUnreachable.isEmpty || !record.undecryptable.isEmpty {
            entries.append(.othersMedia)
        }
        return entries
    }
}
