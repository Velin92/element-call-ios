//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import ElementCallKit
@testable import ElementCallUI
import Foundation
import Testing

/// The core's causes grouped into the list's three entries (034 R13, R23, R29, R38).
@Suite("Interruption entries")
struct InterruptionEntriesTests {
    private let outage = MatrixRTCSignallingHealth.unreachable(since: Date(timeIntervalSince1970: 100))
    
    @Test
    func nothingInterruptedIsNoEntry() {
        #expect(ElementCallInterruption.entries(signalling: .reachable, record: .none).isEmpty)
        #expect(ElementCallInterruption.entries(signalling: .reachable, record: nil).isEmpty)
    }
    
    /// Before media there is no record, and the server is the one cause that can already be known.
    @Test
    func theServerEntryNeedsNoMedia() {
        #expect(ElementCallInterruption.entries(signalling: outage, record: nil)
            == [.ownServer(isMembershipLapsed: false, hasUnverifiedParticipant: false)])
    }
    
    @Test
    func eachSideIsItsOwnEntryInOrder() {
        let record = MatrixRTCInterruptions(signalling: outage,
                                            isOwnMembershipLapsed: true,
                                            ownMedia: .reconnecting,
                                            membersUnreachable: ["@bob:x:B"],
                                            undecryptable: ["@carol:x:C"],
                                            unmappable: ["PA_xyz"])
        
        #expect(ElementCallInterruption.entries(signalling: outage, record: record)
            == [.ownServer(isMembershipLapsed: true, hasUnverifiedParticipant: true), .ownMedia, .othersMedia])
    }
    
    /// One shows up for a moment on every ordinary join, so it says something only while the
    /// homeserver that would introduce them is away.
    @Test
    func anUnmappableParticipantAloneIsNoEntry() {
        let record = MatrixRTCInterruptions(unmappable: ["PA_xyz"])
        #expect(ElementCallInterruption.entries(signalling: .reachable, record: record).isEmpty)
    }
    
    /// Signalling back is not the republish landed: the others still cannot see us until it does.
    @Test
    func aLapseOutlivesTheOutage() {
        let record = MatrixRTCInterruptions(isOwnMembershipLapsed: true)
        #expect(ElementCallInterruption.entries(signalling: .reachable, record: record)
            == [.ownServer(isMembershipLapsed: true, hasUnverifiedParticipant: false)])
    }
    
    @Test
    func anyMemberCauseIsTheOthersEntry() {
        for record in [MatrixRTCInterruptions(membersReconnecting: ["a"]),
                       MatrixRTCInterruptions(membersUnreachable: ["a"]),
                       MatrixRTCInterruptions(undecryptable: ["a"])] {
            #expect(ElementCallInterruption.entries(signalling: .reachable, record: record) == [.othersMedia])
        }
    }
    
    @Test
    func ourOwnMediaUnreachableIsStillOurEntry() {
        let record = MatrixRTCInterruptions(ownMedia: .unreachable)
        #expect(ElementCallInterruption.entries(signalling: .reachable, record: record) == [.ownMedia])
    }
}

/// What an interruption disables, and what it never does (034 R15).
@Suite("Interrupted controls")
@MainActor
struct InterruptedControlsTests {
    typealias Fixtures = ElementCallPreviewFixtures
    
    @Test
    func theHandWaitsForOurServer() {
        var state = Fixtures.connected(tiles: Fixtures.group)
        #expect(state.isHandControlEnabled)
        state.isSignallingReachable = false
        #expect(!state.isHandControlEnabled)
    }
    
    /// A share in progress can always be stopped; only starting one needs our media server.
    @Test
    func onlyStartingAShareWaitsForOurMediaServer() {
        var state = Fixtures.connected(tiles: Fixtures.group, isScreenSharingEnabled: true)
        state.isOwnMediaReconnecting = true
        #expect(!state.isScreenShareControlEnabled)
        state.isScreenSharing = true
        #expect(state.isScreenShareControlEnabled)
    }
}
